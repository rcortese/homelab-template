from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

SCRIPT_RELATIVE = Path("scripts") / "lib" / "compose_defaults.sh"


def _run_script(
    script_path: Path,
    *args: str,
    env: dict[str, str] | None = None,
    expected_returncode: int = 0,
) -> subprocess.CompletedProcess[str]:
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
    assert result.returncode == expected_returncode, result.stderr
    return result


def _ensure_root_compose(repo_copy: Path) -> None:
    compose_root = repo_copy / "docker-compose.yml"
    if not compose_root.exists():
        compose_root.write_text("services: {}\n", encoding="utf-8")


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
    _ensure_root_compose(repo_copy)
    script_path = repo_copy / SCRIPT_RELATIVE
    result = _run_script(script_path, "core", str(repo_copy), env=os.environ.copy())
    stdout = result.stdout

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "docker-compose.yml"
    expected_files = [str((repo_copy / "docker-compose.yml").resolve(strict=False))]

    env_files = _extract_env_files(stdout)
    expected_env_files = [
        str((repo_copy / path).resolve(strict=False))
        for path in compose_instances_data.env_files_map.get("core", [])
        if path
    ]
    assert env_files == expected_env_files

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
    _ensure_root_compose(repo_copy)
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.pop("COMPOSE_FILES", None)
    env.pop("COMPOSE_ENV_FILES", None)
    env.pop("COMPOSE_EXTRA_FILES", None)

    result = _run_script(script_path, "missing", str(repo_copy), env=env)
    stdout = result.stdout

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "docker-compose.yml"

    compose_cmd = _extract_compose_cmd(stdout)
    compose_file_args = _extract_file_args(compose_cmd)
    assert compose_file_args == [
        str((repo_copy / "docker-compose.yml").resolve())
    ]

    env_files = _extract_env_files(stdout)
    expected_env_file = str((repo_copy / "env" / "local" / "common.env").resolve())
    assert env_files == [expected_env_file]

    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    assert env_args == [expected_env_file]


def test_preserves_existing_environment(repo_copy: Path) -> None:
    _ensure_root_compose(repo_copy)
    script_path = repo_copy / SCRIPT_RELATIVE
    custom_env_file = repo_copy / "env" / "local" / "custom.env"
    custom_env_file.write_text("DUMMY=1\n", encoding="utf-8")

    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": "compose/docker-compose.base.yml compose/custom.yml",
            "COMPOSE_ENV_FILES": str(custom_env_file),
        }
    )

    result = _run_script(script_path, "core", str(repo_copy), env=env)
    stdout = result.stdout

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "docker-compose.yml"

    env_files = _extract_env_files(stdout)
    assert env_files == [str(custom_env_file.resolve())]

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    env_args = [
        compose_cmd[index + 1]
        for index, token in enumerate(compose_cmd)
        if token == "--env-file"
    ]
    assert env_args == [str(custom_env_file.resolve())]
    assert _extract_file_args(compose_cmd) == [
        str((repo_copy / "docker-compose.yml").resolve()),
    ]


def test_ignores_compose_file_overrides(repo_copy: Path) -> None:
    _ensure_root_compose(repo_copy)
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": "compose/docker-compose.base.yml compose/custom.yml",
            "COMPOSE_EXTRA_FILES": "compose/extra/metrics.yml",
        }
    )

    result = _run_script(script_path, "core", str(repo_copy), env=env)
    stdout = result.stdout

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "docker-compose.yml"

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == [
        str((repo_copy / "docker-compose.yml").resolve(strict=False))
    ]


def test_respects_docker_compose_bin_override(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    _ensure_root_compose(repo_copy)
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update({"DOCKER_COMPOSE_BIN": "docker --context remote compose"})

    result = _run_script(script_path, "core", str(repo_copy), env=env)
    stdout = result.stdout

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


def test_errors_when_root_compose_missing(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    compose_root = repo_copy / "docker-compose.yml"
    if compose_root.exists():
        compose_root.unlink()

    result = _run_script(
        script_path,
        "core",
        str(repo_copy),
        env=os.environ.copy(),
        expected_returncode=1,
    )
    assert "Missing docker-compose.yml" in result.stderr
