import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_structure.sh"


REQUIRED_PATHS = [
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


def test_script_succeeds_from_subdirectory():
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT / "docs",
    )

    assert result.returncode == 0
    assert "Estrutura do repositório validada com sucesso." in result.stdout


@pytest.mark.parametrize("missing_relative", REQUIRED_PATHS)
def test_missing_required_item_returns_error(tmp_path, missing_relative):
    repo_copy = tmp_path / "repo"
    repo_copy.mkdir()

    for relative in REQUIRED_PATHS:
        source = REPO_ROOT / relative
        destination = repo_copy / relative
        destination.parent.mkdir(parents=True, exist_ok=True)

        if source.is_dir():
            shutil.copytree(source, destination)
        else:
            shutil.copy2(source, destination)

    script_dir = tmp_path / "scripts"
    shutil.copytree(SCRIPT_PATH.parent, script_dir)
    runner_script = script_dir / "check_structure.sh"
    runner_content = runner_script.read_text()
    runner_script.write_text(
        runner_content.replace(
            'ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"',
            'ROOT_DIR="${ROOT_DIR_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"',
        )
    )
    runner_script.chmod(runner_script.stat().st_mode | 0o111)

    missing_path = repo_copy / missing_relative
    if missing_path.is_dir():
        shutil.rmtree(missing_path)
    elif missing_path.exists():
        missing_path.unlink()
    else:
        pytest.fail(f"O caminho {missing_relative} não foi copiado para o diretório temporário.")

    env = os.environ.copy()
    env.update({"CI": "true", "ROOT_DIR_OVERRIDE": str(repo_copy)})

    result = subprocess.run(
        [str(script_dir / "check_structure.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env=env,
    )

    assert result.returncode == 1
    assert missing_relative in result.stderr
    assert "não foram encontrados" in result.stderr
