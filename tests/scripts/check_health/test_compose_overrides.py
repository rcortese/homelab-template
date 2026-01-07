from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub

from .utils import (
    _expected_compose_call,
    expected_consolidated_plan_calls,
    run_check_health,
)


def test_invokes_ps_and_logs_for_instance(docker_stub: DockerStub) -> None:
    repo_root = Path(__file__).resolve().parents[3]

    env = {
        "COMPOSE_ENV_FILES": "env/common.example.env",
    }

    result = run_check_health(args=["core"], env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    expected_env = str((repo_root / "env" / "common.example.env").resolve())
    consolidated_file = repo_root / "docker-compose.yml"

    compose_files = [
        (repo_root / "compose" / "docker-compose.base.yml").resolve(),
        (repo_root / "compose" / "docker-compose.core.yml").resolve(),
    ]
    assert calls == expected_consolidated_plan_calls(
        expected_env, compose_files, consolidated_file
    ) + [
        _expected_compose_call(None, [consolidated_file], "config", "--services"),
        _expected_compose_call(None, [consolidated_file], "ps"),
        _expected_compose_call(
            None,
            [consolidated_file],
            "logs",
            "--tail=50",
            "app",
        ),
    ]
