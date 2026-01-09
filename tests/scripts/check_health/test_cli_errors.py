from __future__ import annotations

import pytest
from pathlib import Path

from tests.conftest import DockerStub

from .utils import (
    expected_consolidated_plan_calls,
    expected_env_for_instance,
    expected_plan_for_instance,
    run_check_health,
)


def test_errors_when_compose_command_missing(repo_copy: Path) -> None:
    env = {"DOCKER_COMPOSE_BIN": "definitely-missing-binary"}

    result = run_check_health(
        args=["core"],
        env=env,
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "check_health.sh",
    )

    assert result.returncode == 127
    assert (
        "Error: definitely-missing-binary is not available. Set DOCKER_COMPOSE_BIN if needed."
        in result.stderr
    )


def test_respects_docker_compose_bin_override(
    docker_stub: DockerStub, repo_copy: Path
) -> None:
    env = {"DOCKER_COMPOSE_BIN": "docker --context remote compose"}

    result = run_check_health(
        args=["core"],
        env=env,
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "check_health.sh",
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    repo_root = repo_copy
    expected_files = [
        str((repo_root / path).resolve())
        for path in expected_plan_for_instance("core", repo_root=repo_copy)
    ]
    consolidated_file = repo_root / "docker-compose.yml"
    base_cmd = ["--context", "remote", "compose"]
    expected_env_files = [
        str((repo_root / path).resolve())
        for path in expected_env_for_instance("core", repo_root=repo_copy)
    ]
    assert calls == expected_consolidated_plan_calls(
        expected_env_files,
        expected_files,
        consolidated_file,
        base_cmd=base_cmd,
    ) + [
        [
            *base_cmd,
            "-f",
            str(consolidated_file),
            "config",
            "--services",
        ],
        [*base_cmd, "-f", str(consolidated_file), "ps"],
        [*base_cmd, "-f", str(consolidated_file), "logs", "--tail=50", "app"],
    ]


@pytest.mark.parametrize("arg", ["-h", "--help"])
def test_help_flags_exit_early_and_show_usage(
    docker_stub: DockerStub, repo_copy: Path, arg: str
) -> None:
    result = run_check_health(
        args=[arg],
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "check_health.sh",
    )

    assert result.returncode == 0, result.stderr
    assert "Usage: scripts/check_health.sh" in result.stdout

    calls = docker_stub.read_calls()
    assert calls == []
