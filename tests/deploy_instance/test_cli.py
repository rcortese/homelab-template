from pathlib import Path

from .utils import run_deploy


def test_unknown_instance_shows_available_options(repo_copy: Path) -> None:
    before_dirs = {
        path.relative_to(repo_copy)
        for path in repo_copy.iterdir()
        if path.is_dir()
    }

    result = run_deploy(repo_copy, "unknown")

    assert result.returncode == 1
    assert "Instância 'unknown' inválida." in result.stderr
    assert "Disponíveis:" in result.stderr

    after_dirs = {
        path.relative_to(repo_copy)
        for path in repo_copy.iterdir()
        if path.is_dir()
    }

    assert after_dirs == before_dirs
