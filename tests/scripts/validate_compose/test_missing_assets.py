from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from tests.helpers.compose_instances import load_compose_instances_data

from .utils import REPO_ROOT


def _select_manifest(repo_copy: Path) -> Path:
    instances = load_compose_instances_data(repo_copy)
    if not instances.instance_names:
        raise AssertionError("No Compose instances found for the test.")

    instance = "core" if "core" in instances.instance_names else instances.instance_names[0]
    for relative in instances.compose_plan(instance):
        relative_path = Path(relative)
        candidate = repo_copy / relative_path
        if candidate.is_file():
            return candidate

    raise AssertionError("No application manifest found for the selected instance.")

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_missing_compose_file_in_temporary_copy(
    tmp_path: Path, docker_stub: DockerStub
) -> None:
    repo_copy = tmp_path / "repo"
    shutil.copytree(REPO_ROOT / "compose", repo_copy / "compose")
    shutil.copytree(REPO_ROOT / "scripts", repo_copy / "scripts")
    shutil.copytree(REPO_ROOT / "env", repo_copy / "env")
    env_local = repo_copy / "env" / "local"
    env_local.mkdir(parents=True, exist_ok=True)
    (env_local / "common.env").write_text(
        "TZ=UTC\nAPP_SECRET=test-secret\nAPP_RETENTION_HOURS=24\nAPP_DATA_UID=1000\nAPP_DATA_GID=1000\n",
        encoding="utf-8",
    )
    for instance in ("core", "media"):
        (env_local / f"{instance}.env").write_text("", encoding="utf-8")

    missing_file = _select_manifest(repo_copy)
    missing_file.unlink()

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "core"},
    )

    assert result.returncode == 0
