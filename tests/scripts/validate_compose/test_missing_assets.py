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
        raise AssertionError("Nenhuma instância Compose encontrada para o teste.")

    apps_without_overrides = sorted(instances.apps_without_overrides())
    if apps_without_overrides:
        app_name = apps_without_overrides[0]
        base_path = instances.app_base_files.get(app_name)
        if base_path:
            candidate = repo_copy / Path(base_path)
            if candidate.is_file():
                return candidate

    instance = "core" if "core" in instances.instance_names else instances.instance_names[0]
    for relative in instances.compose_plan(instance):
        relative_path = Path(relative)
        candidate = repo_copy / relative_path
        if relative_path.parts[:2] == ("compose", "apps") and candidate.is_file():
            return candidate

    raise AssertionError("Nenhum manifest de aplicativo encontrado para a instância selecionada.")

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_missing_compose_file_in_temporary_copy(
    tmp_path: Path, docker_stub: DockerStub
) -> None:
    repo_copy = tmp_path / "repo"
    shutil.copytree(REPO_ROOT / "compose", repo_copy / "compose")
    shutil.copytree(REPO_ROOT / "scripts", repo_copy / "scripts")
    shutil.copytree(REPO_ROOT / "env", repo_copy / "env")

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

    assert result.returncode == 1
    assert f"Application '{missing_file.parent.name}'" in result.stderr
    assert "file missing" in result.stderr
    assert docker_stub.read_calls() == []
