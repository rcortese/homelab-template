from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from .utils import REPO_ROOT

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_missing_compose_file_in_temporary_copy(
    tmp_path: Path, docker_stub: DockerStub
) -> None:
    repo_copy = tmp_path / "repo"
    shutil.copytree(REPO_ROOT / "compose", repo_copy / "compose")
    shutil.copytree(REPO_ROOT / "scripts", repo_copy / "scripts")
    shutil.copytree(REPO_ROOT / "env", repo_copy / "env")

    missing_instance = repo_copy / "compose" / "apps" / "app" / "media.yml"
    missing_instance.unlink()

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "media"},
    )

    assert result.returncode == 1
    assert "arquivo ausente" in result.stderr
    assert "media" in result.stderr
    assert docker_stub.read_calls() == []
