from __future__ import annotations

import pytest
from pathlib import Path

from tests.conftest import DockerStub

from .utils import run_check_health


def test_errors_when_compose_command_missing() -> None:
    env = {"DOCKER_COMPOSE_BIN": "definitely-missing-binary"}

    result = run_check_health(env=env)

    assert result.returncode == 127
    assert (
        "Error: definitely-missing-binary is not available. Set DOCKER_COMPOSE_BIN if needed."
        in result.stderr
    )


def test_respects_docker_compose_bin_override(docker_stub: DockerStub) -> None:
    env = {"DOCKER_COMPOSE_BIN": "docker --context remote compose"}

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    repo_root = Path(__file__).resolve().parents[2]
    base_file = str((repo_root / "compose" / "base.yml").resolve())
    assert calls == [
        [
            "--context",
            "remote",
            "compose",
            "-f",
            base_file,
            "config",
            "--services",
        ],
        [
            "--context",
            "remote",
            "compose",
            "-f",
            base_file,
            "ps",
        ],
        [
            "--context",
            "remote",
            "compose",
            "-f",
            base_file,
            "logs",
            "--tail=50",
            "app",
        ],
    ]


@pytest.mark.parametrize("arg", ["-h", "--help"])
def test_help_flags_exit_early_and_show_usage(
    docker_stub: DockerStub, arg: str
) -> None:
    result = run_check_health(args=[arg])

    assert result.returncode == 0, result.stderr
    assert "Uso: scripts/check_health.sh" in result.stdout

    calls = docker_stub.read_calls()
    assert calls == []
