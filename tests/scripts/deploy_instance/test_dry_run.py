from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

from .utils import _extract_compose_files, run_deploy


def test_dry_run_outputs_planned_commands(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "COMPOSE_ENV_FILES=env/local/common.env env/local/core.env" in result.stdout
    assert "COMPOSE_ENV_FILE=env/local/core.env" in result.stdout
    assert "Planned compose build:" in result.stdout
    assert "Planned Docker Compose command:" in result.stdout
    assert "docker compose -f" in result.stdout
    assert "Planned health check" in result.stdout


def test_dry_run_includes_extra_files_from_env_file(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    for name in ("metrics.yml", "logging.yml"):
        (overlay_dir / name).write_text(
            "version: '3.9'\nservices:\n  placeholder:\n    image: busybox:latest\n",
            encoding="utf-8",
        )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml compose/overlays/logging.yml\n",
        encoding="utf-8",
    )

    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    compose_files = _extract_compose_files(result.stdout)
    expected_plan = compose_instances_data.compose_plan(
        "core", ["compose/overlays/metrics.yml", "compose/overlays/logging.yml"]
    )
    assert compose_files == expected_plan


def test_dry_run_skip_health_outputs_skip_message(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run", "--skip-health")

    assert result.returncode == 0, result.stderr
    assert "Automatic health check skipped (--skip-health flag)." in result.stdout


def test_env_override_takes_precedence_for_extra_files(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    (overlay_dir / "custom.yml").write_text(
        "version: '3.9'\nservices:\n  custom:\n    image: busybox:latest\n",
        encoding="utf-8",
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml\n",
        encoding="utf-8",
    )

    result = run_deploy(
        repo_copy,
        "core",
        "--dry-run",
        env_overrides={"COMPOSE_EXTRA_FILES": "compose/overlays/custom.yml"},
    )

    assert result.returncode == 0, result.stderr
    compose_files = _extract_compose_files(result.stdout)
    expected_plan = compose_instances_data.compose_plan(
        "core", ["compose/overlays/custom.yml"]
    )
    assert compose_files == expected_plan


def test_missing_local_env_file_fails(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    local_env.unlink()

    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 1
    assert "File env/local/core.env not found." in result.stderr
    assert "Copy the default template" in result.stderr
