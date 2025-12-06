from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from .utils import load_app_data_from_deploy_context, run_validate_compose

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_accepts_matching_app_data_overrides(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    docker_stub.set_exit_code(0)

    instance = "core"
    context = load_app_data_from_deploy_context(repo_copy, instance)

    env = {
        "COMPOSE_INSTANCES": instance,
        "APP_DATA_DIR": context["APP_DATA_DIR"],
        "APP_DATA_DIR_MOUNT": context["APP_DATA_DIR_MOUNT"],
    }

    result = run_validate_compose(env, cwd=repo_copy)

    assert result.returncode == 0, result.stderr

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 2
    assert env_records[-1].get("APP_DATA_DIR") == context["APP_DATA_DIR"]
    assert env_records[-1].get("APP_DATA_DIR_MOUNT") == context["APP_DATA_DIR_MOUNT"]

    conflict_mount = Path(context["APP_DATA_DIR_MOUNT"]).parent / "mismatch"
    conflict_env = {
        "COMPOSE_INSTANCES": instance,
        "APP_DATA_DIR": context["APP_DATA_DIR"],
        "APP_DATA_DIR_MOUNT": str(conflict_mount),
    }

    conflict_result = run_validate_compose(conflict_env, cwd=repo_copy)

    assert conflict_result.returncode != 0
    assert "APP_DATA_DIR and APP_DATA_DIR_MOUNT" in conflict_result.stderr

    calls_after_conflict = docker_stub.read_calls()
    assert len(calls_after_conflict) == 2
