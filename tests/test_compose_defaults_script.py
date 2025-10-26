from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

SCRIPT_RELATIVE = Path("scripts") / "lib" / "compose_defaults.sh"


def _run_script(script_path: Path, *args: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        [str(script_path), *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
        cwd=script_path.parent.parent.parent,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def _extract_value(pattern: str, stdout: str) -> str:
    match = re.search(pattern, stdout)
    assert match is not None, f"Pattern {pattern!r} not found in {stdout!r}"
    return match.group(1)


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
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
    ]
    assert compose_files == " ".join(expected_files)

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    expected_env_file = repo_copy / "env" / "local" / "core.env"
    assert env_file == str(expected_env_file)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    assert "--env-file" in compose_cmd
    assert str(expected_env_file) in compose_cmd
    assert _extract_file_args(compose_cmd) == expected_files


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

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    assert env_file == str(custom_env_file)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    assert compose_cmd.count("--env-file") == 1
    assert compose_cmd[compose_cmd.index("--env-file") + 1] == str(custom_env_file)
    assert _extract_file_args(compose_cmd) == ["compose/base.yml", "compose/custom.yml"]


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
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/overlays/metrics.yml",
        "compose/overlays/logging.yml",
    ]
    assert compose_files == " ".join(expected_files)

    compose_cmd = _extract_compose_cmd(stdout)
    assert _extract_file_args(compose_cmd) == expected_files


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
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        *overlays,
    ]
    assert _extract_file_args(compose_cmd) == expected_files


def test_respects_docker_compose_bin_override(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    env = os.environ.copy()
    env.update({"DOCKER_COMPOSE_BIN": "docker --context remote compose"})

    stdout = _run_script(script_path, "core", str(repo_copy), env=env)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:4] == ["docker", "--context", "remote", "compose"]

    env_file = str(repo_copy / "env" / "local" / "core.env")
    assert "--env-file" in compose_cmd
    assert env_file in compose_cmd
