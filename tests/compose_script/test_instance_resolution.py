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

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 1
    assert env_records[0].get("APP_DATA_DIR") == "data/app-core"
    assert env_records[0].get("APP_DATA_DIR_MOUNT") == "../data/app-core"

    env_files = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "--env-file"
    ]
    assert env_files == [
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]

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


def test_instance_with_absolute_app_data_dir(repo_copy: Path, docker_stub: DockerStub) -> None:
    absolute_data_dir = (repo_copy / "absolute-app-storage").resolve()

    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR={absolute_data_dir}\n",
        encoding="utf-8",
    )

    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 1
    assert env_records[0].get("APP_DATA_DIR") == str(absolute_data_dir)
    assert env_records[0].get("APP_DATA_DIR_MOUNT") == str(absolute_data_dir)
