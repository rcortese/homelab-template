"""Compose metadata discovery helpers for env sync checks."""

from __future__ import annotations

import ast
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Mapping, Sequence

PAIR_PATTERN = re.compile(
    r"\[([^\]]+)\]="
    r"("  # opening group for value alternatives
    r"\$'[^'\\]*(?:\\.[^'\\]*)*'"  # $'...'
    r'|"[^"\\]*(?:\\.[^"\\]*)*"'  # "..."
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
