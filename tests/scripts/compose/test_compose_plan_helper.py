from __future__ import annotations

import re
import shlex
import subprocess
from pathlib import Path

from tests.scripts.compose_instances.test_compose_instances_script import (
    _collect_compose_metadata,
)


def run_compose_plan(
    repo_root: Path,
    instance: str,
    *,
    extras: list[str] | None = None,
    capture_metadata: bool = False,
) -> subprocess.CompletedProcess[str]:
    extras = extras or []
    extras_literal = " ".join(shlex.quote(item) for item in extras)
    extras_assignment = f"extras=({extras_literal})" if extras_literal else "extras=()"
    capture_flag = "1" if capture_metadata else "0"

    compose_instances_path = repo_root / "scripts" / "lib" / "compose_instances.sh"
    compose_plan_path = repo_root / "scripts" / "lib" / "compose_plan.sh"

    script = f"""
set -euo pipefail
repo_root={shlex.quote(str(repo_root))}
metadata="$({shlex.quote(str(compose_instances_path))} \"$repo_root\")"
eval "$metadata"
source {shlex.quote(str(compose_plan_path))}
declare -a plan=()
{extras_assignment}
if [[ {capture_flag} -eq 1 ]]; then
  declare -A meta=()
  build_compose_file_plan {shlex.quote(instance)} plan extras meta
  declare -p plan
  declare -p meta
else
  build_compose_file_plan {shlex.quote(instance)} plan extras
  declare -p plan
fi
"""

    return subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
    )


def find_declare_line(stdout: str, variable: str) -> str:
    token = f"{variable}="
    for line in stdout.splitlines():
        if line.startswith("declare ") and token in line:
            return line
    raise AssertionError(f"Variable {variable} not found in output: {stdout!r}")


def parse_indexed_values(line: str) -> list[str]:
    matches = re.findall(r"\[(\d+)\]=\"([^\"]*)\"", line)
    return [value for _, value in sorted(((int(index), value) for index, value in matches))]


def parse_mapping(line: str) -> dict[str, str]:
    pattern = re.compile(r"\[([^\]]+)\]=(\$'[^']*'|\"[^\"]*\"|'[^']*')")
    mapping: dict[str, str] = {}

    for key, raw_value in pattern.findall(line):
        value = raw_value
        if value.startswith("$'"):
            inner = value[2:-1]
            value = bytes(inner, "utf-8").decode("unicode_escape")
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        elif value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        mapping[key] = value

    return mapping


def build_expected_plan(
    base_file: str,
    instance: str,
    app_names_map: dict[str, list[str]],
    app_base_map: dict[str, str],
    instance_files_map: dict[str, list[str]],
) -> list[str]:
    expected: list[str] = []

    def append_unique(entry: str) -> None:
        if entry and entry not in expected:
            expected.append(entry)

    append_unique(base_file)

    instance_candidates = instance_files_map.get(instance, [])
    instance_level_overrides = [
        candidate
        for candidate in instance_candidates
        if not candidate.startswith("compose/apps/")
    ]
    for override in instance_level_overrides:
        append_unique(override)

    for app_name in app_names_map.get(instance, []):
        app_base = app_base_map.get(app_name, "")
        append_unique(app_base)
        for candidate in instance_files_map.get(instance, []):
            prefix = f"compose/apps/{app_name}/"
            if candidate.startswith(prefix):
                append_unique(candidate)

    for candidate in instance_files_map.get(instance, []):
        append_unique(candidate)

    return expected


def test_compose_plan_matches_existing_logic(repo_copy: Path) -> None:
    (
        expected_names,
        expected_files_map,
        expected_app_names_map,
        expected_app_base_map,
        _env_local_map,
        _env_template_map,
        _env_file_map,
    ) = _collect_compose_metadata(repo_copy)

    base_file = "compose/base.yml" if (repo_copy / "compose" / "base.yml").exists() else ""

    for instance in expected_names:
        result = run_compose_plan(repo_copy, instance)
        assert result.returncode == 0, result.stderr

        plan_line = find_declare_line(result.stdout, "plan")
        plan_entries = parse_indexed_values(plan_line)

        expected_plan = build_expected_plan(
            base_file,
            instance,
            expected_app_names_map,
            expected_app_base_map,
            expected_files_map,
        )

        assert plan_entries == expected_plan
        assert "compose/apps/overrideonly/base.yml" not in plan_entries


def test_compose_plan_appends_extra_files(repo_copy: Path) -> None:
    extras = ["compose/custom-extra.yml"]
    if (repo_copy / "compose" / "base.yml").exists():
        extras.append("compose/base.yml")
    result = run_compose_plan(repo_copy, "core", extras=extras)

    assert result.returncode == 0, result.stderr

    plan_line = find_declare_line(result.stdout, "plan")
    plan_entries = parse_indexed_values(plan_line)

    (
        _names,
        expected_files_map,
        expected_app_names_map,
        expected_app_base_map,
        _env_local_map,
        _env_template_map,
        _env_file_map,
    ) = _collect_compose_metadata(repo_copy)

    expected_plan = build_expected_plan(
        "compose/base.yml" if (repo_copy / "compose" / "base.yml").exists() else "",
        "core",
        expected_app_names_map,
        expected_app_base_map,
        expected_files_map,
    )
    expected_plan.extend(extras)

    assert plan_entries == expected_plan


def test_compose_plan_optional_metadata(repo_copy: Path) -> None:
    extras = ["compose/optional.yml"]
    result = run_compose_plan(repo_copy, "core", extras=extras, capture_metadata=True)

    assert result.returncode == 0, result.stderr

    meta_line = find_declare_line(result.stdout, "meta")
    metadata = parse_mapping(meta_line)

    (
        _names,
        expected_files_map,
        expected_app_names_map,
        expected_app_base_map,
        _env_local_map,
        _env_template_map,
        _env_file_map,
    ) = _collect_compose_metadata(repo_copy)

    assert metadata["app_names"].splitlines() == expected_app_names_map["core"]
    assert metadata["discovered_files"].splitlines() == expected_files_map["core"]
    assert metadata["extra_files"].splitlines() == extras
