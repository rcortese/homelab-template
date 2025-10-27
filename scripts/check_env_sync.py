#!/usr/bin/env python3
"""Check that Docker Compose manifests and env templates stay in sync."""

from __future__ import annotations

import argparse
import ast
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Sequence, Set

VAR_PATTERN = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)[^}]*\}")
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
    base_file: Path
    instances: Sequence[str]
    files_by_instance: Mapping[str, Sequence[Path]]
    app_names_by_instance: Mapping[str, Sequence[str]]
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
        raise ComposeMetadataError(result.stderr.strip() or "Falha ao descobrir instâncias Compose.")

    base_file: Path | None = None
    instances: List[str] = []
    files_map: Dict[str, List[Path]] = {}
    env_templates: Dict[str, Path | None] = {}
    app_names_map: Dict[str, List[str]] = {}

    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("declare -- BASE_COMPOSE_FILE="):
            _, _, tail = line.partition("=")
            base_value = decode_bash_string(tail)
            base_file = (repo_root / base_value).resolve()
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
        elif line.startswith("declare -A COMPOSE_INSTANCE_APP_NAMES="):
            raw_map = parse_declare_mapping(line)
            for instance, value in raw_map.items():
                app_names_map[instance] = [
                    entry for entry in (item.strip() for item in value.splitlines()) if entry
                ]

    if base_file is None or not base_file.exists():
        raise ComposeMetadataError("Arquivo compose/base.yml não encontrado.")
    if not instances:
        raise ComposeMetadataError("Nenhuma instância Compose detectada.")

    normalized_files_map: Dict[str, Sequence[Path]] = {}
    for instance in instances:
        files = files_map.get(instance)
        if not files:
            raise ComposeMetadataError(f"Nenhum override localizado para a instância '{instance}'.")
        normalized_files_map[instance] = files

    normalized_app_names: Dict[str, Sequence[str]] = {}
    for instance in instances:
        normalized_app_names[instance] = app_names_map.get(instance, [])

    return ComposeMetadata(
        base_file=base_file,
        instances=instances,
        files_by_instance=normalized_files_map,
        app_names_by_instance=normalized_app_names,
        env_template_by_instance=env_templates,
    )


def extract_compose_variables(paths: Iterable[Path]) -> Set[str]:
    variables: Set[str] = set()
    for path in paths:
        try:
            content = path.read_text(encoding="utf-8")
        except FileNotFoundError as exc:
            raise ComposeMetadataError(f"Arquivo Compose ausente: {path}") from exc
        for match in VAR_PATTERN.finditer(content):
            variables.add(match.group(1))
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
    base_vars = extract_compose_variables([metadata.base_file])
    compose_vars_by_instance: Dict[str, Set[str]] = {}
    for instance, files in metadata.files_by_instance.items():
        instance_vars = set(base_vars)
        app_names = metadata.app_names_by_instance.get(instance, [])
        app_base_files = []
        for app in app_names:
            base_candidate = repo_root / "compose" / "apps" / app / "base.yml"
            if base_candidate.exists():
                app_base_files.append(base_candidate)
                continue

            has_override = False
            for override in files:
                try:
                    relative = override.resolve().relative_to(repo_root)
                except Exception:  # pragma: no cover - defensive
                    continue
                parts = relative.parts
                if len(parts) >= 4 and parts[0] == "compose" and parts[1] == "apps" and parts[2] == app:
                    has_override = True
                    break

            if not has_override:
                raise ComposeMetadataError(f"Arquivo Compose ausente: {base_candidate}")

        if app_base_files:
            instance_vars.update(extract_compose_variables(app_base_files))
        instance_vars.update(extract_compose_variables(files))
        compose_vars_by_instance[instance] = instance_vars

    common_env_path = repo_root / "env" / "common.example.env"
    instance_env_files: Dict[Path, EnvTemplateData] = {}
    if common_env_path.exists():
        common_env_vars = load_env_variables(common_env_path).available
    else:
        common_env_vars = set()

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
    lines.append("Verificando variáveis de ambiente referenciadas pelos manifests Compose...")
    lines.append("")

    for instance, missing in sorted(report.missing_by_instance.items()):
        if not missing:
            continue
        lines.append(f"Instância '{instance}':")
        for var in sorted(missing):
            lines.append(f"  - Variável ausente: {var}")
        lines.append("")

    for template in sorted(report.missing_templates):
        lines.append(f"Instância '{template}' não possui arquivo env/<instancia>.example.env documentado.")
    if report.missing_templates:
        lines.append("")

    for path, unused in sorted(report.unused_by_file.items(), key=lambda item: str(item[0])):
        rel_path = path.relative_to(repo_root)
        lines.append(f"Variáveis obsoletas em {rel_path}:")
        for var in sorted(unused):
            lines.append(f"  - {var}")
        lines.append("")

    if not report.has_issues:
        lines.append("Todas as variáveis de ambiente estão sincronizadas.")
    else:
        lines.append("Divergências encontradas entre manifests Compose e arquivos .env exemplo.")

    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def determine_exit_code(report: SyncReport) -> int:
    return 1 if report.has_issues else 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Valida variáveis .env em relação aos manifests Compose.")
    parser.add_argument(
        "--repo-root",
        dest="repo_root",
        default=None,
        help="Diretório raiz do repositório (padrão: diretório pai de scripts/).",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[1]

    try:
        metadata = load_compose_metadata(repo_root)
        report = build_sync_report(repo_root, metadata)
    except ComposeMetadataError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(f"[!] Arquivo esperado não encontrado: {exc}", file=sys.stderr)
        return 1

    output = format_report(repo_root, report)
    print(output)
    return determine_exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
