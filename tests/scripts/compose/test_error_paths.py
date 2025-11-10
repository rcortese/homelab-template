from __future__ import annotations

from pathlib import Path

from .utils import run_compose_in_repo


def test_unknown_instance_returns_error(repo_copy: Path) -> None:
    result = run_compose_in_repo(repo_copy, args=["unknown"])

    assert result.returncode == 1
    assert "instância desconhecida 'unknown'" in result.stderr
    assert "Disponíveis:" in result.stderr
    assert "core" in result.stderr
    assert "media" in result.stderr


def test_missing_compose_file_is_allowed(repo_copy: Path) -> None:
    missing_file = repo_copy / "compose" / "base.yml"
    assert missing_file.exists()
    missing_file.unlink()

    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0, result.stderr
    assert "Error: não foi possível carregar metadados das instâncias." not in result.stderr
