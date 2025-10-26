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
    repo_root = Path(__file__).resolve().parents[2]
    expected_env = str((repo_root / "env" / "custom.env").resolve())

    compose_files = [
        (repo_root / "compose" / "base.yml").resolve(),
        (repo_root / "compose" / "extra.yml").resolve(),
    ]
    assert calls == [
        _expected_compose_call(expected_env, compose_files, "config", "--services"),
        _expected_compose_call(expected_env, compose_files, "ps"),
        _expected_compose_call(
            expected_env,
            compose_files,
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

    repo_root = Path(__file__).resolve().parents[2]
    expected_files = [
        (repo_root / "compose" / "base.yml").resolve(),
        (repo_root / "compose" / "overlays" / "extra.yml").resolve(),
    ]
    calls = docker_stub.read_calls()
    assert calls == [
        _expected_compose_call(str(env_file), expected_files, "config", "--services"),
        _expected_compose_call(str(env_file), expected_files, "ps"),
        _expected_compose_call(str(env_file), expected_files, "logs", "--tail=50", "app-extra"),
        _expected_compose_call(str(env_file), expected_files, "logs", "--tail=50", "app"),
    ]
