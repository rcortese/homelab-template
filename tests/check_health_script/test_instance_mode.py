from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub

from .utils import _expected_compose_call, run_check_health


def test_infers_compose_files_and_env_from_instance(
    docker_stub: DockerStub, repo_copy: Path
) -> None:
    script_path = repo_copy / "scripts" / "check_health.sh"

    result = run_check_health(
        args=["core"],
        cwd=repo_copy,
        script_path=script_path,
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    env_file = "env/local/core.env"
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
    ]
    assert calls == [
        _expected_compose_call(env_file, expected_files, "config", "--services"),
        _expected_compose_call(env_file, expected_files, "ps"),
        _expected_compose_call(env_file, expected_files, "logs", "--tail=50", "app-core"),
    ]


def test_executes_from_scripts_directory(docker_stub: DockerStub, repo_copy: Path) -> None:
    scripts_dir = repo_copy / "scripts"

    result = run_check_health(
        args=["core"],
        cwd=scripts_dir,
        script_path="./check_health.sh",
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    env_file = "env/local/core.env"
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
    ]
    assert calls == [
        _expected_compose_call(env_file, expected_files, "config", "--services"),
        _expected_compose_call(env_file, expected_files, "ps"),
        _expected_compose_call(env_file, expected_files, "logs", "--tail=50", "app-core"),
        _expected_compose_call(env_file, expected_files, "logs", "--tail=50", "app"),
    ]
