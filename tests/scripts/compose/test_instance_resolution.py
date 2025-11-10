from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Iterable
from typing import TYPE_CHECKING

from .utils import run_compose, run_compose_in_repo

if TYPE_CHECKING:
    from ..conftest import DockerStub


def _load_compose_plan(repo_root: Path, instance: str) -> list[Path]:
    script = f"""
set -euo pipefail
source '{repo_root / "scripts" / "lib" / "compose_plan.sh"}'
metadata="$('{repo_root / "scripts" / "lib" / "compose_instances.sh"}' '{repo_root}')"
eval "$metadata"
declare -a plan=()
if build_compose_file_plan '{instance}' plan; then
  printf '%s\\n' "${{plan[@]}}"
fi
"""

    result = subprocess.run(
        ["bash", "-c", script],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr

    plan_files: list[Path] = []
    for entry in (line.strip() for line in result.stdout.splitlines() if line.strip()):
        path = Path(entry)
        if not path.is_absolute():
            path = (repo_root / path).resolve()
        plan_files.append(path)

    return plan_files


def _extract_flag_values(command: Iterable[str], flag: str) -> list[str]:
    command_list = list(command)
    values: list[str] = []
    for index, arg in enumerate(command_list):
        if arg == flag and index + 1 < len(command_list):
            values.append(command_list[index + 1])
    return values


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
    app_data_dir = env_records[0].get("APP_DATA_DIR")
    assert app_data_dir == "data/core/app"

    assert env_records[0].get("LOCAL_INSTANCE") == "core"

    expected_base = (repo_copy / app_data_dir).resolve()
    mount_value = env_records[0].get("APP_DATA_DIR_MOUNT")
    assert mount_value is not None
    mount_path = Path(mount_value)
    assert mount_path.is_absolute()
    assert mount_path == expected_base

    expected_env_files = [
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    ]
    expected_compose_files = [str(path) for path in _load_compose_plan(repo_copy, "core")]

    expected_command: list[str] = ["compose"]
    for env_file in expected_env_files:
        expected_command.extend(["--env-file", env_file])
    for compose_file in expected_compose_files:
        expected_command.extend(["-f", compose_file])

    assert command == expected_command

    env_files = _extract_flag_values(command, "--env-file")
    assert env_files == expected_env_files

    compose_files = _extract_flag_values(command, "-f")
    assert compose_files == expected_compose_files


def test_media_instance_exports_local_instance_and_defaults(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    result = run_compose_in_repo(repo_copy, args=["media"])

    assert result.returncode == 0

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 1

    record = env_records[0]
    assert record.get("LOCAL_INSTANCE") == "media"
    assert record.get("APP_DATA_DIR") == "data/media/app"

    mount_value = record.get("APP_DATA_DIR_MOUNT")
    assert mount_value is not None
    mount_path = Path(mount_value)
    assert mount_path.is_absolute()

    expected_base = (repo_copy / "data" / "media" / "app").resolve()
    assert mount_path == expected_base


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

    compose_files = _extract_flag_values(command, "-f")
    expected_compose_files = [
        str(path) for path in _load_compose_plan(repo_copy, "core")
    ]
    assert compose_files == expected_compose_files


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
    assert env_records[0].get("LOCAL_INSTANCE") == "core"
    expected_relative = absolute_data_dir.relative_to(repo_copy.resolve()).as_posix()
    assert env_records[0].get("APP_DATA_DIR") == expected_relative
    assert env_records[0].get("APP_DATA_DIR_MOUNT") == f"{absolute_data_dir}/app"


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
    assert env_records[0].get("LOCAL_INSTANCE") == "core"
    assert env_records[0].get("APP_DATA_DIR") == "data/core/app"
    expected_mount = (repo_copy / "data" / "core" / "app").resolve()
    assert env_records[0].get("APP_DATA_DIR_MOUNT") == str(expected_mount)


def test_instance_with_only_mount_defined(repo_copy: Path, docker_stub: DockerStub) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR_MOUNT=/srv/external\n",
        encoding="utf-8",
    )

    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 1
    assert env_records[0].get("LOCAL_INSTANCE") == "core"
    assert env_records[0].get("APP_DATA_DIR") == "data/core/app"
    mount_path = Path(env_records[0]["APP_DATA_DIR_MOUNT"])
    assert mount_path.is_absolute()
    assert mount_path == Path("/srv/external/app")


def test_instance_with_conflicting_app_data_configuration(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        (
            f"{existing_content}APP_DATA_DIR=custom-storage\n"
            "APP_DATA_DIR_MOUNT=/srv/external\n"
        ),
        encoding="utf-8",
    )

    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode != 0
    assert "APP_DATA_DIR e APP_DATA_DIR_MOUNT" in result.stderr
    assert docker_stub.read_calls() == []
