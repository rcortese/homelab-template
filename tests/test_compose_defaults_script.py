from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

SCRIPT_RELATIVE = Path("scripts") / "lib" / "compose_defaults.sh"


def _run_script(script_path: Path, *args: str, env: dict[str, str] | None = None) -> str:
    stub_dir = script_path.parent / ".docker-stub"
    stub_dir.mkdir(exist_ok=True)
    docker_stub = stub_dir / "docker"
    docker_stub.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    docker_stub.chmod(0o755)

    env_vars = os.environ.copy()
    if env:
        env_vars.update(env)
    env_vars["PATH"] = f"{stub_dir}{os.pathsep}{env_vars.get('PATH', '')}"

    result = subprocess.run(
        [str(script_path), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env_vars,
        cwd=script_path.parent.parent.parent,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def _extract_value(pattern: str, stdout: str) -> str:
    match = re.search(pattern, stdout)
    assert match is not None, f"Pattern {pattern!r} not found in {stdout!r}"
    return match.group(1)


def _extract_env_files(stdout: str) -> list[str]:
    match = re.search(r"COMPOSE_ENV_FILES=([^\n]+)", stdout)
    assert match is not None, f"COMPOSE_ENV_FILES not found in {stdout!r}"
    value = match.group(1)
    if value.startswith("$'") and value.endswith("'"):
        value = value[2:-1].encode("utf-8").decode("unicode_escape")
    elif value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    entries = [entry for entry in value.replace("\n", " ").split() if entry]
    return entries


def _extract_compose_cmd(stdout: str) -> list[str]:
    line_match = re.search(r"declare -a COMPOSE_CMD=\((.*)\)", stdout, flags=re.S)
    assert line_match is not None, f"COMPOSE_CMD declaration not found in {stdout!r}"
    return re.findall(r'"([^"]+)"', line_match.group(1))


def _extract_file_args(compose_cmd: list[str]) -> list[str]:
    return [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "-f"
    ]


def test_defaults_for_core_instance(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    stdout = _run_script(script_path, "core", str(repo_copy), env=os.environ.copy())

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    compose_entries = compose_files.split()
    expected_relative = compose_instances_data.compose_plan("core")
    assert compose_entries == expected_relative

    assert compose_instances_data.base_file in compose_entries

    core_apps = compose_instances_data.instance_app_names.get("core", [])
    core_overrides = compose_instances_data.instance_files.get("core", [])
    for app in core_apps:
        base_file = compose_instances_data.app_base_files.get(app, "")
        overrides = [
            entry
            for entry in core_overrides
            if entry.startswith(f"compose/apps/{app}/")
        ]
        if base_file:
            assert base_file in compose_entries
        if overrides:
            for override in overrides:
                assert override in compose_entries
        else:
            assert base_file, f"Aplicação '{app}' deveria possuir base quando não há overrides"
        if app not in compose_instances_data.app_base_files:
            base_candidate = f"compose/apps/{app}/base.yml"
            assert base_candidate not in compose_entries

    expected_files = [
        str((repo_copy / path).resolve(strict=False))
        for path in expected_relative
    ]

    env_files = _extract_env_files(stdout)
    expected_env_files = [
        str((repo_copy / path).resolve(strict=False))
        for path in compose_instances_data.env_files_map.get("core", [])
        if path
    ]
    assert env_files == expected_env_files

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    assert env_file == (expected_env_files[-1] if expected_env_files else "")

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    assert env_args == expected_env_files
    assert _extract_file_args(compose_cmd) == expected_files


def test_fallbacks_when_instance_missing(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.pop("COMPOSE_FILES", None)
    env.pop("COMPOSE_ENV_FILE", None)
    env.pop("COMPOSE_ENV_FILES", None)
    env.pop("COMPOSE_EXTRA_FILES", None)

    stdout = _run_script(script_path, "missing", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "compose/base.yml"

    compose_cmd = _extract_compose_cmd(stdout)
    compose_file_args = _extract_file_args(compose_cmd)
    assert compose_file_args == [str((repo_copy / "compose" / "base.yml").resolve())]

    env_files = _extract_env_files(stdout)
    expected_env_file = str((repo_copy / "env" / "local" / "common.env").resolve())
    assert env_files == [expected_env_file]

    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    assert env_args == [expected_env_file]

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    assert env_file == expected_env_file


def test_preserves_existing_environment(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    custom_env_file = repo_copy / "env" / "local" / "custom.env"
    custom_env_file.write_text("DUMMY=1\n", encoding="utf-8")

    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": "compose/base.yml compose/custom.yml",
            "COMPOSE_ENV_FILE": str(custom_env_file),
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "compose/base.yml compose/custom.yml"

    env_files = _extract_env_files(stdout)
    assert env_files == [str(custom_env_file.resolve())]

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    assert env_file == str(custom_env_file)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    assert env_args == [str(custom_env_file.resolve())]
    assert _extract_file_args(compose_cmd) == [
        str((repo_copy / "compose" / "base.yml").resolve()),
        str((repo_copy / "compose" / "custom.yml").resolve()),
    ]


def test_appends_extra_files_when_defined(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    base_plan = compose_instances_data.compose_plan("core")
    subset_length = min(3, len(base_plan)) or 1
    existing_files = base_plan[:subset_length]
    env = os.environ.copy()
    overlays = ["compose/overlays/metrics.yml", "compose/overlays/logging.yml"]
    env.update(
        {
            "COMPOSE_FILES": " ".join(existing_files),
            "COMPOSE_EXTRA_FILES": " ".join(overlays),
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [*existing_files, *overlays]
    expected_files = [
        str((repo_copy / path).resolve(strict=False)) for path in expected_relative
    ]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == expected_files


def test_handles_comma_and_newline_separated_extra_files(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    base_plan = compose_instances_data.compose_plan("core")
    subset_length = min(3, len(base_plan)) or 1
    existing_files = base_plan[:subset_length]
    overlays = ["compose/overlays/metrics.yml", "compose/overlays/logging.yml"]
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": " ".join(existing_files),
            "COMPOSE_EXTRA_FILES": f"{overlays[0]}, {overlays[1]}\n{overlays[0]}",
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [*existing_files, *overlays]
    expected_files = [
        str((repo_copy / path).resolve(strict=False)) for path in expected_relative
    ]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == expected_files


def test_removes_duplicate_entries(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    base_plan = compose_instances_data.compose_plan("core")
    unique_base: list[str] = []
    for entry in base_plan:
        if entry not in unique_base:
            unique_base.append(entry)
        if len(unique_base) >= 2:
            break
    if not unique_base:
        unique_base = base_plan[:1]
    primary = unique_base[0]
    secondary = unique_base[1] if len(unique_base) > 1 else primary
    overlays = ["compose/overlays/logging.yml", "compose/overlays/metrics.yml"]
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": f"{primary} {secondary} {secondary} {overlays[0]}",
            "COMPOSE_EXTRA_FILES": (
                f"{overlays[0]} {overlays[1]} {primary}"
            ),
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [primary]
    if secondary != primary:
        expected_relative.append(secondary)
    expected_relative.extend(overlays)
    expected_files = [
        str((repo_copy / path).resolve(strict=False)) for path in expected_relative
    ]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    file_args = _extract_file_args(compose_cmd)
    assert file_args == expected_files
    assert len(file_args) == len(set(file_args))


def test_loads_extra_files_from_env_file(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env_file = repo_copy / "env" / "local" / "core.env"
    overlays = [
        "compose/overlays/metrics.yml",
        "compose/overlays/logging.yml",
    ]
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + f"COMPOSE_EXTRA_FILES={', '.join(overlays)}\n",
        encoding="utf-8",
    )

    env = os.environ.copy()
    env.pop("COMPOSE_EXTRA_FILES", None)

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_cmd = _extract_compose_cmd(stdout)
    expected_relative = compose_instances_data.compose_plan("core", overlays)
    expected_files = [
        str((repo_copy / path).resolve(strict=False)) for path in expected_relative
    ]
    assert _extract_file_args(compose_cmd) == expected_files


def test_respects_docker_compose_bin_override(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update({"DOCKER_COMPOSE_BIN": "docker --context remote compose"})

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:4] == ["docker", "--context", "remote", "compose"]
    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    expected_env_files = [
        str((repo_copy / relative).resolve(strict=False))
        for relative in compose_instances_data.env_files_map.get("core", [])
        if relative
    ]
    assert env_args == expected_env_files
