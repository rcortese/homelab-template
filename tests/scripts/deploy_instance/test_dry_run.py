from pathlib import Path

from .utils import run_deploy


def test_dry_run_outputs_planned_commands(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "COMPOSE_ENV_FILES=env/local/common.env env/local/core.env" in result.stdout
    assert "Planned compose build:" in result.stdout
    assert "Planned Docker Compose command:" in result.stdout
    assert "docker compose -f" in result.stdout
    assert "Planned health check" in result.stdout


def test_dry_run_skip_health_outputs_skip_message(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run", "--skip-health")

    assert result.returncode == 0, result.stderr
    assert "Automatic health check skipped (--skip-health flag)." in result.stdout


def test_missing_local_env_file_fails(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    local_env.unlink()

    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 1
    assert "File env/local/core.env not found." in result.stderr
    assert "Copy the default template" in result.stderr
