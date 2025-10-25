import os
import subprocess
from pathlib import Path

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover - hints only
    from .conftest import DockerStub


def run_deploy(
    repo_copy: Path, *args: str, env_overrides: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    command = [str(repo_copy / "scripts" / "deploy_instance.sh"), *args]
    env = {**os.environ}
    if env_overrides:
        env.update(env_overrides)
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env=env,
    )


def test_unknown_instance_shows_available_options(repo_copy: Path) -> None:
    before_dirs = {
        path.relative_to(repo_copy)
        for path in repo_copy.iterdir()
        if path.is_dir()
    }

    result = run_deploy(repo_copy, "unknown")

    assert result.returncode == 1
    assert "compose/unknown.yml" in result.stderr
    assert "Disponíveis:" in result.stderr

    after_dirs = {
        path.relative_to(repo_copy)
        for path in repo_copy.iterdir()
        if path.is_dir()
    }

    assert after_dirs == before_dirs


def test_dry_run_outputs_planned_commands(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "COMPOSE_ENV_FILE=env/local/core.env" in result.stdout
    assert "Docker Compose planejado:" in result.stdout
    assert "compose.sh core -- up -d" in result.stdout
    assert "Health check planejado" in result.stdout


def test_dry_run_includes_extra_files_from_env_file(repo_copy: Path) -> None:
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
    assert (
        "COMPOSE_FILES=compose/base.yml compose/core.yml compose/overlays/metrics.yml "
        "compose/overlays/logging.yml"
    ) in result.stdout


def test_dry_run_skip_health_outputs_skip_message(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run", "--skip-health")

    assert result.returncode == 0, result.stderr
    assert "Health check automático ignorado (flag --skip-health)." in result.stdout


def test_env_override_takes_precedence_for_extra_files(repo_copy: Path) -> None:
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
    assert (
        "COMPOSE_FILES=compose/base.yml compose/core.yml compose/overlays/custom.yml"
    ) in result.stdout


def test_missing_local_env_file_fails(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    local_env.unlink()

    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 1
    assert "Arquivo env/local/core.env não encontrado" in result.stderr
    assert "Copie o template padrão" in result.stderr


def test_deploy_without_privileges_skips_chown(
    repo_copy: Path, docker_stub: "DockerStub"
) -> None:
    fake_bin = repo_copy / "fake-bin"
    fake_bin.mkdir()

    fake_id = fake_bin / "id"
    fake_id.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$1\" == '-u' ]]; then\n"
        "  echo 1000\n"
        "else\n"
        "  exec /usr/bin/id \"$@\"\n"
        "fi\n",
        encoding="utf-8",
    )
    fake_id.chmod(0o755)

    env_overrides = {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "CI": "1",
    }

    result = run_deploy(
        repo_copy,
        "core",
        "--skip-structure",
        "--skip-validate",
        "--skip-health",
        "--force",
        env_overrides=env_overrides,
    )

    assert result.returncode == 0, result.stderr
    assert (
        "Owner desejado 1000:1000 não aplicado (permissões insuficientes)."
        in result.stdout
    )

    expected_dirs = {
        repo_copy / "data",
        repo_copy / "data/app-core",
        repo_copy / "data/app",
        repo_copy / "backups",
    }

    for directory in expected_dirs:
        assert directory.exists(), directory


def test_deploy_without_service_name_uses_compose_services(
    repo_copy: Path, docker_stub: "DockerStub"
) -> None:
    env_file = repo_copy / "env" / "local" / "core.env"
    env_lines = [
        line
        for line in env_file.read_text(encoding="utf-8").splitlines()
        if not line.startswith("SERVICE_NAME=")
    ]
    env_file.write_text("\n".join(env_lines) + "\n", encoding="utf-8")

    fake_bin = repo_copy / "fake-bin"
    fake_bin.mkdir()
    fake_id = fake_bin / "id"
    fake_id.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$1\" == '-u' ]]; then\n"
        "  echo 0\n"
        "else\n"
        "  exec /usr/bin/id \"$@\"\n"
        "fi\n",
        encoding="utf-8",
    )
    fake_id.chmod(0o755)

    env_overrides = {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "CI": "1",
        "DOCKER_STUB_SERVICES_OUTPUT": "app\nworker",
    }

    result = run_deploy(
        repo_copy,
        "core",
        "--skip-structure",
        "--skip-validate",
        "--skip-health",
        "--force",
        env_overrides=env_overrides,
    )

    assert result.returncode == 0, result.stderr
    assert (repo_copy / "data").exists()
    assert (repo_copy / "data/app").exists()
    assert (repo_copy / "data/worker").exists()
    assert not (repo_copy / "data/app-core").exists()
    assert (repo_copy / "backups").exists()
