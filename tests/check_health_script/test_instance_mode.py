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
        env={"DOCKER_STUB_SERVICES_OUTPUT": "app\nmonitoring"},
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    expected_env_files = [
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]
    expected_files = [
        str((repo_copy / "compose" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "core.yml").resolve()),
    ]
    assert calls == [
        _expected_compose_call(expected_env_files, expected_files, "config", "--services"),
        _expected_compose_call(expected_env_files, expected_files, "ps"),
        _expected_compose_call(expected_env_files, expected_files, "logs", "--tail=50", "app-core"),
    ]


def test_executes_from_scripts_directory(docker_stub: DockerStub, repo_copy: Path) -> None:
    scripts_dir = repo_copy / "scripts"

    result = run_check_health(
        args=["core"],
        cwd=scripts_dir,
        script_path="./check_health.sh",
        env={"DOCKER_STUB_SERVICES_OUTPUT": "app\nmonitoring"},
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    expected_env_files = [
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]
    expected_files = [
        str((repo_copy / "compose" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "core.yml").resolve()),
    ]
    assert calls == [
        _expected_compose_call(expected_env_files, expected_files, "config", "--services"),
        _expected_compose_call(expected_env_files, expected_files, "ps"),
        _expected_compose_call(expected_env_files, expected_files, "logs", "--tail=50", "app-core"),
        _expected_compose_call(expected_env_files, expected_files, "logs", "--tail=50", "app"),
        _expected_compose_call(expected_env_files, expected_files, "logs", "--tail=50", "monitoring"),
    ]
