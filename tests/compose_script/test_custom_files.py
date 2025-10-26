from __future__ import annotations

import shutil
from pathlib import Path
from typing import TYPE_CHECKING

from .utils import run_compose_in_repo

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_custom_compose_files_override(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    apps_dir = repo_copy / "compose" / "apps"
    if apps_dir.exists():
        shutil.rmtree(apps_dir)

    custom_compose = repo_copy / "compose" / "custom.yml"
    override_compose = repo_copy / "compose" / "override.yml"
    custom_compose.write_text("version: '3.8'\n", encoding="utf-8")
    override_compose.write_text("version: '3.8'\n", encoding="utf-8")

    result = run_compose_in_repo(
        repo_copy,
        args=["core", "--", "ps"],
        env={"COMPOSE_FILES": "compose/custom.yml compose/override.yml"},
    )

    assert result.returncode == 0

    calls = docker_stub.read_calls()
    assert len(calls) == 1
    command = calls[0]

    assert "--env-file" in command
    env_arg_index = command.index("--env-file")
    assert command[env_arg_index + 1].endswith("env/local/core.env")

    compose_files = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "-f"
    ]
    assert compose_files == [
        "compose/custom.yml",
        "compose/override.yml",
    ]
