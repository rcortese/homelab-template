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
    env_record = env_records[0]
    expected_mount = str((repo_copy / "data" / "app-core" / "app").resolve())
    assert env_record.get("APP_DATA_DIR") == "data/app-core"
    assert env_record.get("APP_DATA_DIR_MOUNT") == expected_mount
    assert env_record.get("APP_DATA_DIR_MOUNT_IS_ABSOLUTE") == "true"

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
        str((repo_copy / "compose" / "apps" / "worker" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "worker" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "baseonly" / "base.yml").resolve()),
    ]

    expected_command = ["compose"]
    expected_command.extend([
        "--env-file",
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        "--env-file",
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ])
    expected_command.extend([
        "-f",
        str((repo_copy / "compose" / "base.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "app" / "base.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "app" / "core.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "monitoring" / "base.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "monitoring" / "core.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "worker" / "base.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "worker" / "core.yml").resolve()),
        "-f",
        str((repo_copy / "compose" / "apps" / "baseonly" / "base.yml").resolve()),
    ])
    assert command == expected_command


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
        str((repo_copy / "compose" / "apps" / "worker" / "base.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "worker" / "core.yml").resolve()),
        str((repo_copy / "compose" / "apps" / "baseonly" / "base.yml").resolve()),
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
    env_record = env_records[0]
    expected_mount = str((absolute_data_dir / "app").resolve())
    assert env_record.get("APP_DATA_DIR") == str(absolute_data_dir)
    assert env_record.get("APP_DATA_DIR_MOUNT") == expected_mount
    assert env_record.get("APP_DATA_DIR_MOUNT_IS_ABSOLUTE") == "true"


def test_instance_with_empty_app_data_dir_falls_back_to_default(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR=\n",
        encoding="utf-8",
    )

    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 1
    env_record = env_records[0]
    expected_mount = str((repo_copy / "data" / "app-core" / "app").resolve())
    assert env_record.get("APP_DATA_DIR") == "data/app-core"
    assert env_record.get("APP_DATA_DIR_MOUNT") == expected_mount
    assert env_record.get("APP_DATA_DIR_MOUNT_IS_ABSOLUTE") == "true"


def test_instance_with_conflicting_app_data_inputs_exits_with_error(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    result = run_compose_in_repo(
        repo_copy,
        args=["core"],
        env={
            "APP_DATA_DIR": "data/app-core",
            "APP_DATA_DIR_MOUNT": "/tmp/custom",
        },
    )

    assert result.returncode != 0
    assert "APP_DATA_DIR e APP_DATA_DIR_MOUNT" in result.stderr

    assert docker_stub.read_calls() == []
