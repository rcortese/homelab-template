import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_structure.sh"


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_help_displays_usage(flag):
    result = subprocess.run(
        [str(SCRIPT_PATH), flag],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "Uso: scripts/check_structure.sh" in result.stdout


def test_script_succeeds_on_repository_root():
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert result.returncode == 0
    assert "Estrutura do repositório validada com sucesso." in result.stdout


def test_missing_required_item_returns_error(tmp_path):
    required_paths = [
        "compose",
        "env",
        "scripts",
        "docs",
        ".github/workflows",
        "README.md",
        "docs/STRUCTURE.md",
        "scripts/check_structure.sh",
        "scripts/validate_compose.sh",
        ".github/workflows/template-quality.yml",
    ]

    for relative in required_paths:
        source = REPO_ROOT / relative
        destination = tmp_path / relative
        destination.parent.mkdir(parents=True, exist_ok=True)

        if source.is_dir():
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source, destination)
        else:
            shutil.copy2(source, destination)

    missing_path = tmp_path / "docs" / "STRUCTURE.md"
    missing_path.unlink()

    result = subprocess.run(
        [str(tmp_path / "scripts" / "check_structure.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=tmp_path,
        env={**os.environ, "CI": "true"},
    )

    assert result.returncode == 1
    assert "docs/STRUCTURE.md" in result.stderr
    assert "não foram encontrados" in result.stderr
