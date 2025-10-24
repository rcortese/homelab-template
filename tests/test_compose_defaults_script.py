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


def test_defaults_for_core_instance(repo_copy: Path) -> None:
    script_path = repo_copy / SCRIPT_RELATIVE
    stdout = _run_script(script_path, "core", str(repo_copy), env=os.environ.copy())

    compose_files = _extract_value(r'COMPOSE_FILES="([^"]+)"', stdout)
    assert compose_files == "compose/base.yml compose/core.yml"

    env_file = _extract_value(r'COMPOSE_ENV_FILE="([^"]*)"', stdout)
    expected_env_file = repo_copy / "env" / "local" / "core.env"
    assert env_file == str(expected_env_file)

    compose_cmd = _extract_compose_cmd(stdout)
    assert compose_cmd[:2] == ["docker", "compose"]
    assert "--env-file" in compose_cmd
    assert str(expected_env_file) in compose_cmd
    assert compose_cmd.count("-f") == 2
    assert "compose/base.yml" in compose_cmd
    assert "compose/core.yml" in compose_cmd


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
    assert compose_cmd.count("-f") == 2
    assert compose_cmd[compose_cmd.index("-f") + 1] == "compose/base.yml"
    assert compose_cmd[compose_cmd.index("-f", compose_cmd.index("-f") + 1) + 1] == "compose/custom.yml"
