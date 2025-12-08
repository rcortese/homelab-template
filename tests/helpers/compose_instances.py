from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class ComposeInstancesData:
    base_file: str
    instance_names: list[str]
    instance_files: dict[str, list[str]]
    env_local_map: dict[str, str]
    env_template_map: dict[str, str]
    env_files_map: dict[str, list[str]]

    @property
    def instance_app_names(self) -> dict[str, list[str]]:
        return {}

    @property
    def app_base_files(self) -> dict[str, str]:
        return {}

    def compose_plan(self, instance: str, extra_files: Iterable[str] | None = None) -> list[str]:
        plan: list[str] = []

        def append_unique(entry: str) -> None:
            value = entry.strip()
            if not value:
                return
            if value not in plan:
                plan.append(value)

        append_unique(self.base_file)

        for override in self.instance_files.get(instance, []):
            append_unique(override)

        if extra_files is not None:
            for extra in extra_files:
                append_unique(extra)

        return plan

    def apps_without_overrides(self) -> set[str]:
        return set()

def _find_declare_line(stdout: str, variable: str) -> str:
    pattern = re.compile(r"^declare[^=]*\b" + re.escape(variable) + "=", re.MULTILINE)
    for line in stdout.splitlines():
        if pattern.search(line):
            return line
    raise AssertionError(f"Variable {variable} not found in output: {stdout!r}")


def _decode_shell_value(raw: str) -> str:
    if raw.startswith("$'") and raw.endswith("'"):
        return bytes(raw[2:-1], "utf-8").decode("unicode_escape")
    if raw.startswith("'") and raw.endswith("'"):
        return raw[1:-1]
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    return raw


def _parse_indexed_values(line: str) -> list[str]:
    matches = re.findall(r"\[(\d+)\]=\"([^\"]*)\"", line)
    ordered = sorted(((int(index), value) for index, value in matches), key=lambda item: item[0])
    return [value for _, value in ordered]


def _parse_mapping(line: str) -> dict[str, str]:
    pattern = re.compile(r"\[([^\]]+)\]=(\$'[^']*'|\"[^\"]*\"|'[^']*')")
    mapping: dict[str, str] = {}
    for key, raw_value in pattern.findall(line):
        mapping[key] = _decode_shell_value(raw_value)
    return mapping


def load_compose_instances_data(repo_root: Path) -> ComposeInstancesData:
    script_path = repo_root / "scripts" / "lib" / "compose_instances.sh"
    result = subprocess.run(
        [str(script_path), str(repo_root)],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "compose_instances.sh failed")

    base_line = _find_declare_line(result.stdout, "BASE_COMPOSE_FILE")
    base_match = re.search(r"=\"([^\"]*)\"", base_line)
    if base_match is None:
        raise AssertionError(f"BASE_COMPOSE_FILE not found in: {base_line!r}")
    base_file = base_match.group(1)

    names_line = _find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    instance_names = _parse_indexed_values(names_line)

    files_line = _find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map_raw = _parse_mapping(files_line)
    files_map = {
        key: [entry for entry in value.splitlines() if entry]
        for key, value in files_map_raw.items()
    }

    env_local_line = _find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_LOCAL")
    env_local_map = _parse_mapping(env_local_line)

    env_template_line = _find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_TEMPLATES")
    env_template_map = _parse_mapping(env_template_line)

    env_files_line = _find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_FILES")
    env_files_map_raw = _parse_mapping(env_files_line)
    env_files_map = {
        key: [entry for entry in value.splitlines() if entry]
        for key, value in env_files_map_raw.items()
    }

    return ComposeInstancesData(
        base_file=base_file,
        instance_names=instance_names,
        instance_files=files_map,
        env_local_map=env_local_map,
        env_template_map=env_template_map,
        env_files_map=env_files_map,
    )
