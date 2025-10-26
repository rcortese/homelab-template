from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from .utils import run_compose_in_repo

if TYPE_CHECKING:
    from ..conftest import DockerStub


def _ensure_monitoring_app(repo_root: Path) -> None:
    monitoring_dir = repo_root / "compose" / "apps" / "monitoring"
    monitoring_dir.mkdir(parents=True, exist_ok=True)

    base_file = monitoring_dir / "base.yml"
    if not base_file.exists():
        base_file.write_text("services: {}\n", encoding="utf-8")

    core_file = monitoring_dir / "core.yml"
    if not core_file.exists():
        core_file.write_text("services: {}\n", encoding="utf-8")


def test_compose_uses_all_app_bases_for_instance(
    repo_copy: Path, docker_stub: "DockerStub"
) -> None:
    _ensure_monitoring_app(repo_copy)

    result = run_compose_in_repo(repo_copy, args=["core"])

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
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/monitoring/base.yml",
        "compose/apps/app/core.yml",
        "compose/apps/monitoring/core.yml",
    ]
