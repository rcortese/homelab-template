from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub

from .utils import _expected_compose_call, run_check_health


def test_invokes_ps_and_logs_with_custom_files(docker_stub: DockerStub) -> None:
    env = {
        "COMPOSE_FILES": "compose/base.yml compose/extra.yml",
        "COMPOSE_ENV_FILE": "env/custom.env",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        _expected_compose_call("env/custom.env", ["compose/base.yml", "compose/extra.yml"], "config", "--services"),
        _expected_compose_call("env/custom.env", ["compose/base.yml", "compose/extra.yml"], "ps"),
        _expected_compose_call(
            "env/custom.env",
            ["compose/base.yml", "compose/extra.yml"],
            "logs",
            "--tail=50",
            "app",
        ),
    ]


def test_loads_compose_extra_files_from_env_file(
    docker_stub: DockerStub, tmp_path: Path
) -> None:
    env_file = tmp_path / "custom.env"
    env_file.write_text(
        "COMPOSE_EXTRA_FILES=compose/overlays/extra.yml\n"
        "SERVICE_NAME=app-extra\n",
        encoding="utf-8",
    )

    env = {
        "COMPOSE_FILES": "compose/base.yml",
        "COMPOSE_ENV_FILE": str(env_file),
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning:" not in result.stderr

    expected_files = [
        "compose/base.yml",
        "compose/overlays/extra.yml",
        "compose/overlays/extra.yml",
    ]
    calls = docker_stub.read_calls()
    assert calls == [
        _expected_compose_call(str(env_file), expected_files, "config", "--services"),
        _expected_compose_call(str(env_file), expected_files, "ps"),
        _expected_compose_call(str(env_file), expected_files, "logs", "--tail=50", "app-extra"),
        _expected_compose_call(str(env_file), expected_files, "logs", "--tail=50", "app"),
    ]
