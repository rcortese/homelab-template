from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from .utils import run_validate_compose

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_derives_local_instance_for_compose(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    docker_stub.set_exit_code(0)

    instance = "core"
    result = run_validate_compose({"COMPOSE_INSTANCES": instance}, cwd=repo_copy)

    assert result.returncode == 0, result.stderr

    env_records = docker_stub.read_call_env()
    assert len(env_records) == 2
    assert env_records[-1].get("LOCAL_INSTANCE") == instance


def test_rejects_legacy_app_data_overrides(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    result = run_validate_compose({"COMPOSE_INSTANCES": "core"}, cwd=repo_copy)

    assert result.returncode != 0
    assert "APP_DATA_DIR and APP_DATA_DIR_MOUNT are no longer supported" in result.stderr
