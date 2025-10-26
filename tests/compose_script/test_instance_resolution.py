from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from .utils import run_compose, run_compose_in_repo

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_instance_uses_expected_env_and_compose_files(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0

    calls = docker_stub.read_calls()
    assert len(calls) == 1
    command = calls[0]

    env_args = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "--env-file"
    ]
    expected_envs = {
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    }
    assert set(env_args) == expected_envs

    compose_files = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "-f"
    ]
    assert compose_files == [
        str((repo_copy / "compose" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "core.yml").resolve()),
    ]


def test_instance_resolves_manifests_when_invoked_from_scripts_dir(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    scripts_dir = repo_copy / "scripts"

    result = run_compose(
        args=["core"],
        cwd=scripts_dir,
        script_path=scripts_dir / "compose.sh",
    )

    assert result.returncode == 0

    calls = docker_stub.read_calls()
    assert len(calls) == 1
    command = calls[0]

    compose_files = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "-f"
    ]
    assert compose_files == [
        str((repo_copy / "compose" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "app" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "monitoring" / "core.yml").resolve()),
    ]
