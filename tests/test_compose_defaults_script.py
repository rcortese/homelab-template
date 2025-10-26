from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

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


def test_defaults_for_core_instance(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    stdout = _run_script(script_path, "core", str(repo_copy), env=os.environ.copy())

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/apps/monitoring/base.yml",
        "compose/apps/monitoring/core.yml",
        "compose/apps/baseonly/base.yml",
    ]
    expected_files = [
        str((repo_copy / path).resolve())
        for path in expected_relative
    ]
    assert compose_files == " ".join(expected_relative)

    env_files = _extract_env_files(stdout)
    expected_env_files = [
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]
    assert env_files == expected_env_files

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    assert env_file == expected_env_files[-1]

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


def test_appends_extra_files_when_defined(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": "compose/base.yml compose/apps/app/base.yml compose/apps/app/core.yml",
            "COMPOSE_EXTRA_FILES": "compose/overlays/metrics.yml compose/overlays/logging.yml",
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/overlays/metrics.yml",
        "compose/overlays/logging.yml",
    ]
    expected_files = [str((repo_copy / path).resolve()) for path in expected_relative]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == expected_files


def test_handles_comma_and_newline_separated_extra_files(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": "compose/base.yml compose/apps/app/base.yml compose/apps/app/core.yml",
            "COMPOSE_EXTRA_FILES": (
                "compose/overlays/metrics.yml, compose/overlays/logging.yml\n"
                "compose/overlays/metrics.yml"
            ),
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/overlays/metrics.yml",
        "compose/overlays/logging.yml",
    ]
    expected_files = [str((repo_copy / path).resolve()) for path in expected_relative]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == expected_files


def test_removes_duplicate_entries(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update(
        {
            "COMPOSE_FILES": (
                "compose/base.yml "
                "compose/apps/app/base.yml "
                "compose/apps/app/base.yml "
                "compose/overlays/logging.yml"
            ),
            "COMPOSE_EXTRA_FILES": (
                "compose/overlays/logging.yml "
                "compose/overlays/metrics.yml "
                "compose/apps/app/base.yml"
            ),
        }
    )

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    expected_relative = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/overlays/logging.yml",
        "compose/overlays/metrics.yml",
    ]
    expected_files = [str((repo_copy / path).resolve()) for path in expected_relative]
    assert compose_files == " ".join(expected_relative)

    compose_cmd = _extract_compose_cmd(stdout)
    file_args = _extract_file_args(compose_cmd)
    assert file_args == expected_files
    assert len(file_args) == len(set(file_args))


def test_loads_extra_files_from_env_file(repo_copy: Path) -> None:
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
    expected_relative = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/apps/monitoring/base.yml",
        "compose/apps/monitoring/core.yml",
        "compose/apps/baseonly/base.yml",
        *overlays,
    ]
    expected_files = [str((repo_copy / path).resolve()) for path in expected_relative]
    assert _extract_file_args(compose_cmd) == expected_files


def test_respects_docker_compose_bin_override(repo_copy: Path) -> None:
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
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]
    assert env_args == expected_env_files
