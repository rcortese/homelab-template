#!/usr/bin/env python3
"""Check that Docker Compose manifests and env templates stay in sync."""

from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
from collections.abc import Mapping as MappingCollection
from collections.abc import Sequence as SequenceCollection
from collections.abc import Set as SetCollection
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Sequence, Set

import yaml

RUNTIME_PROVIDED_VARIABLES: Set[str] = {"PWD"}
# Additional variables implicitly accepted by the project without being listed in
# env templates. Projects can provide overrides in scripts/local/check_env_sync.py
# (if present); otherwise the allowlist is empty by default.
try:  # pragma: no cover - optional local overrides
    from scripts.local.check_env_sync import IMPLICIT_ENV_VARS  # type: ignore[attr-defined]
except ModuleNotFoundError:  # pragma: no cover - default fallback
    IMPLICIT_ENV_VARS: Set[str] = set()

PAIR_PATTERN = re.compile(
    r"\[([^\]]+)\]="
    r"("  # opening group for value alternatives
    r"\$'[^'\\]*(?:\\.[^'\\]*)*'"  # $'...'
    r"|\"[^\"\\]*(?:\\.[^\"\\]*)*\""  # "..."
    r"|'[^'\\]*(?:\\.[^'\\]*)*'"  # '...'
    r")"
)


@dataclass
class ComposeMetadata:
    base_file: Path | None
    instances: Sequence[str]
    files_by_instance: Mapping[str, Sequence[Path]]
    env_template_by_instance: Mapping[str, Path | None]


class ComposeMetadataError(RuntimeError):
    """Raised when compose metadata cannot be loaded."""


def decode_bash_string(token: str) -> str:
    token = token.strip()
    if token.startswith("$'") and token.endswith("'"):
        inner = token[2:-1]
        return bytes(inner, "utf-8").decode("unicode_escape")
    try:
        return ast.literal_eval(token)
    except Exception:  # pragma: no cover - fallback for unexpected formats
        return token


def parse_declare_array(line: str) -> List[str]:
    values: Dict[int, str] = {}
    for match in PAIR_PATTERN.finditer(line):
        key = match.group(1)
        value = decode_bash_string(match.group(2))
        try:
            index = int(key)
        except ValueError:  # pragma: no cover - defensive programming
            continue
        values[index] = value
    return [value for index, value in sorted(values.items())]


def parse_declare_mapping(line: str) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    for match in PAIR_PATTERN.finditer(line):
        key = match.group(1)
        value = decode_bash_string(match.group(2))
        mapping[key] = value
    return mapping


def load_compose_metadata(repo_root: Path) -> ComposeMetadata:
    script_path = repo_root / "scripts" / "lib" / "compose_instances.sh"
    result = subprocess.run(
        [str(script_path)],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ComposeMetadataError(
            result.stderr.strip() or "Failed to discover Compose instances."
        )

    base_file: Path | None = None
    instances: List[str] = []
    files_map: Dict[str, List[Path]] = {}
    env_templates: Dict[str, Path | None] = {}

    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("declare -- BASE_COMPOSE_FILE="):
            _, _, tail = line.partition("=")
            base_value = decode_bash_string(tail)
            if base_value:
                candidate = (repo_root / base_value).resolve()
                if not candidate.exists():
                    raise ComposeMetadataError(
                        f"Declared base file is missing: {candidate}"
                    )
                base_file = candidate
            else:
                base_file = None
        elif line.startswith("declare -a COMPOSE_INSTANCE_NAMES="):
            instances = parse_declare_array(line)
        elif line.startswith("declare -A COMPOSE_INSTANCE_FILES="):
            raw_map = parse_declare_mapping(line)
            for instance, value in raw_map.items():
                files_map[instance] = [
                    (repo_root / entry).resolve()
                    for entry in value.splitlines()
                    if entry.strip()
                ]
        elif line.startswith("declare -A COMPOSE_INSTANCE_ENV_TEMPLATES="):
            raw_map = parse_declare_mapping(line)
            for instance, value in raw_map.items():
                env_templates[instance] = (repo_root / value).resolve() if value else None

    if base_file is not None and not base_file.exists():
        raise ComposeMetadataError("compose/base.yml file not found.")
    if not instances:
        raise ComposeMetadataError("No Compose instances detected.")

    normalized_files_map: Dict[str, Sequence[Path]] = {}
    for instance in instances:
        files = files_map.get(instance, [])
        if not files:
            normalized_files_map[instance] = ()
            continue
        normalized_files_map[instance] = files

    return ComposeMetadata(
        base_file=base_file,
        instances=instances,
        files_by_instance=normalized_files_map,
        env_template_by_instance=env_templates,
    )


def _collect_substitution_variables(text: str) -> Set[str]:
    """Collect variable names from Docker Compose substitution expressions."""

    variables: Set[str] = set()
    length = len(text)
    index = 0

    while index < length:
        char = text[index]
        if char == "$":
            if index > 0 and text[index - 1] == "$":
                index += 1
                continue
            if text.startswith("$$${", index):
                index += 1
                continue
            next_index = index + 1
            if next_index < length and text[next_index] == "{":
                brace_depth = 1
                inner_start = next_index + 1
                cursor = inner_start
                while cursor < length and brace_depth:
                    current = text[cursor]
                    if current == "{":
                        brace_depth += 1
                    elif current == "}":
                        brace_depth -= 1
                    cursor += 1
                if brace_depth == 0:
                    inner_expression = text[inner_start : cursor - 1]
                    variables.update(_parse_parameter_expression(inner_expression))
                    index = cursor
                    continue
            else:
                if next_index < length and (
                    text[next_index].isalpha() or text[next_index] == "_"
                ):
                    cursor = next_index + 1
                    while cursor < length and (
                        text[cursor].isalnum() or text[cursor] == "_"
                    ):
                        cursor += 1
                    variables.add(text[next_index:cursor])
                    index = cursor
                    continue
        index += 1

    return variables


def _strip_inline_comment(text: str) -> str:
    """Remove inline comments while keeping quoted "#" characters."""

    result: List[str] = []
    in_single = False
    in_double = False
    escape = False

    for char in text:
        if escape:
            result.append(char)
            escape = False
            continue
        if char == "\\":
            result.append(char)
            escape = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            result.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            result.append(char)
            continue
        if char == "#" and not in_single and not in_double:
            break
        result.append(char)

    return "".join(result)


def _collect_variables_from_text(text: str) -> Set[str]:
    """Fallback variable extraction that ignores comment-only lines."""

    variables: Set[str] = set()
    for raw_line in text.splitlines():
        stripped = raw_line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        cleaned = _strip_inline_comment(stripped)
        if cleaned:
            variables.update(_collect_substitution_variables(cleaned))
    return variables


def _parse_parameter_expression(expression: str) -> Set[str]:
    expression = expression.strip()
    if not expression:
        return set()

    variables: Set[str] = set()

    index = 0
    length = len(expression)

    while index < length and expression[index] == "!":
        index += 1

    start = index
    if index < length and (
        expression[index].isalpha() or expression[index] == "_"
    ):
        index += 1
        while index < length and (
            expression[index].isalnum() or expression[index] == "_"
        ):
            index += 1
        variable_name = expression[start:index]
        if variable_name:
            variables.add(variable_name)

    remainder = expression[index:]
    if remainder:
        variables.update(_collect_substitution_variables(remainder))

    return variables


def _iter_yaml_strings(node: object) -> Iterable[str]:
    if isinstance(node, str):
        yield node
        return
    if isinstance(node, MappingCollection):
        for value in node.values():
            yield from _iter_yaml_strings(value)
        return
    if isinstance(node, SequenceCollection) and not isinstance(node, (str, bytes, bytearray)):
        for item in node:
            yield from _iter_yaml_strings(item)
        return
    if isinstance(node, SetCollection):
        for item in node:
            yield from _iter_yaml_strings(item)


def extract_compose_variables(paths: Iterable[Path]) -> Set[str]:
    variables: Set[str] = set()
    for path in paths:
        try:
            content = path.read_text(encoding="utf-8")
        except FileNotFoundError as exc:
            raise ComposeMetadataError(f"Compose file missing: {path}") from exc
        try:
            for document in yaml.safe_load_all(content):
                for value in _iter_yaml_strings(document):
                    variables.update(_collect_substitution_variables(value))
        except yaml.YAMLError as exc:  # pragma: no cover - defensive parsing fallback
            print(
                f"[!] Failed to parse YAML in {path}: {exc}. Using heuristic fallback.",
                file=sys.stderr,
            )
            variables.update(_collect_variables_from_text(content))
    return variables


@dataclass
class EnvTemplateData:
    defined: Set[str]
    documented: Set[str]

    @property
    def available(self) -> Set[str]:
        return self.defined | self.documented


def load_env_variables(path: Path) -> EnvTemplateData:
    lines = path.read_text(encoding="utf-8").splitlines()
    defined: Set[str] = set()
    documented: Set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        is_comment = stripped.startswith("#")
        candidate = stripped[1:] if is_comment else stripped
        candidate = candidate.strip()

        if candidate.startswith("export "):
            candidate = candidate[len("export ") :].lstrip()

        if "=" not in candidate:
            continue

        name, _ = candidate.split("=", 1)
        name = name.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
            continue

        if is_comment:
            documented.add(name)
        else:
            defined.add(name)
    return EnvTemplateData(defined=defined, documented=documented)


@dataclass
class SyncReport:
    missing_by_instance: Mapping[str, Set[str]]
    unused_by_file: Mapping[Path, Set[str]]
    missing_templates: Sequence[str]

    @property
    def has_issues(self) -> bool:
        return (
            any(values for values in self.missing_by_instance.values())
            or any(values for values in self.unused_by_file.values())
            or bool(self.missing_templates)
        )


def build_sync_report(repo_root: Path, metadata: ComposeMetadata) -> SyncReport:
    variable_cache: Dict[Path, Set[str]] = {}

    def cached_compose_variables(path: Path) -> Set[str]:
        normalized = path.resolve()
        cached = variable_cache.get(normalized)
        if cached is None:
            cached = extract_compose_variables([normalized])
            variable_cache[normalized] = cached
        return cached

    def gather_variables(paths: Sequence[Path]) -> Set[str]:
        collected: Set[str] = set()
        for entry in paths:
            collected.update(cached_compose_variables(entry))
        return collected

    base_sources: list[Path] = []
    if metadata.base_file is not None:
        base_sources.append(metadata.base_file)

    base_vars = gather_variables(base_sources)
    compose_vars_by_instance: Dict[str, Set[str]] = {}
    for instance, files in metadata.files_by_instance.items():
        instance_vars = set(base_vars)
        instance_vars.update(gather_variables(files))
        compose_vars_by_instance[instance] = instance_vars

    common_env_path = repo_root / "env" / "common.example.env"
    local_common_path = repo_root / "env" / "local" / "common.env"
    instance_env_files: Dict[Path, EnvTemplateData] = {}

    empty_env_data = EnvTemplateData(defined=set(), documented=set())
    common_env_data = load_env_variables(common_env_path) if common_env_path.exists() else empty_env_data
    local_common_data = (
        load_env_variables(local_common_path) if local_common_path.exists() else empty_env_data
    )
    common_env_vars = set(common_env_data.available)
    common_env_vars.update(local_common_data.available)
    implicit_env_vars = globals().get("IMPLICIT_ENV_VARS")
    if implicit_env_vars:
        common_env_vars.update(set(implicit_env_vars))

    missing_templates: List[str] = []
    for instance in metadata.instances:
        template_path = metadata.env_template_by_instance.get(instance)
        if template_path is None or not template_path.exists():
            missing_templates.append(instance)
            continue
        instance_env_files[template_path] = load_env_variables(template_path)

    missing_by_instance: Dict[str, Set[str]] = {}
    for instance, compose_vars in compose_vars_by_instance.items():
        template_path = metadata.env_template_by_instance.get(instance)
        data = instance_env_files.get(template_path) if template_path else None
        instance_env_vars = data.available if data else set()
        available = set(common_env_vars)
        available.update(RUNTIME_PROVIDED_VARIABLES)
        available.update(instance_env_vars)
        missing_by_instance[instance] = compose_vars - available

    unused_by_file: Dict[Path, Set[str]] = {}
    for path, data in instance_env_files.items():
        instance = next(
            (name for name, template in metadata.env_template_by_instance.items() if template == path),
            None,
        )
        relevant_compose = compose_vars_by_instance.get(instance, set())
        unused = data.defined - relevant_compose
        if unused:
            unused_by_file[path] = unused

    return SyncReport(
        missing_by_instance=missing_by_instance,
        unused_by_file=unused_by_file,
        missing_templates=missing_templates,
    )


def format_report(repo_root: Path, report: SyncReport) -> str:
    lines: List[str] = []
    lines.append("Checking environment variables referenced by Compose manifests...")
    lines.append("")

    for instance, missing in sorted(report.missing_by_instance.items()):
        if not missing:
            continue
        lines.append(f"Instance '{instance}':")
        for var in sorted(missing):
            lines.append(f"  - Missing variable: {var}")
        lines.append("")

    for template in sorted(report.missing_templates):
        lines.append(
            f"Instance '{template}' does not have a documented env/<instance>.example.env file."
        )
    if report.missing_templates:
        lines.append("")

    for path, unused in sorted(report.unused_by_file.items(), key=lambda item: str(item[0])):
        rel_path = path.relative_to(repo_root)
        lines.append(f"Obsolete variables in {rel_path}:")
        for var in sorted(unused):
            lines.append(f"  - {var}")
        lines.append("")

    if not report.has_issues:
        lines.append("All environment variables are in sync.")
    else:
        lines.append("Differences found between Compose manifests and example .env files.")

    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def determine_exit_code(report: SyncReport) -> int:
    return 1 if report.has_issues else 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate .env variables against Compose manifests."
    )
    parser.add_argument(
        "--repo-root",
        dest="repo_root",
        default=None,
        help="Repository root directory (default: parent of scripts/).",
    )
    parser.add_argument(
        "--instance",
        dest="instances",
        action="append",
        default=None,
        help=(
            "Restrict validation to the provided instances. Can be repeated or supplied as a comma-separated list."
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[1]

    try:
        metadata = load_compose_metadata(repo_root)
        if args.instances:
            requested_instances: List[str] = []
            seen: Set[str] = set()
            for raw_value in args.instances:
                parts = [part.strip() for part in raw_value.split(",") if part.strip()]
                if not parts:
                    continue
                for candidate in parts:
                    if candidate not in seen:
                        requested_instances.append(candidate)
                        seen.add(candidate)

            if not requested_instances:
                print("[!] No valid instance was provided.", file=sys.stderr)
                return 1

            known_instances = set(metadata.instances)
            missing_instances = sorted(set(requested_instances) - known_instances)
            if missing_instances:
                formatted = ", ".join(missing_instances)
                print(f"[!] Unknown instances: {formatted}.", file=sys.stderr)
                return 1

            filtered_instances = [
                instance for instance in metadata.instances if instance in seen
            ]
            files_by_instance = {
                instance: metadata.files_by_instance[instance]
                for instance in filtered_instances
            }
            env_template_by_instance = {
                instance: metadata.env_template_by_instance.get(instance)
                for instance in filtered_instances
            }

            metadata = ComposeMetadata(
                base_file=metadata.base_file,
                instances=filtered_instances,
                files_by_instance=files_by_instance,
                env_template_by_instance=env_template_by_instance,
            )

        report = build_sync_report(repo_root, metadata)
    except ComposeMetadataError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(f"[!] Expected file not found: {exc}", file=sys.stderr)
        return 1

    output = format_report(repo_root, report)
    print(output)
    return determine_exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
