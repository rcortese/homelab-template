from pathlib import Path

from .utils import _extract_compose_files, run_deploy


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


def test_dry_run_reports_all_application_bases(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    compose_files = _extract_compose_files(result.stdout)
    assert compose_files[:5] == [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/apps/monitoring/base.yml",
        "compose/apps/monitoring/core.yml",
    ]

