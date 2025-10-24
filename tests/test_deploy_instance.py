import os
import subprocess
from pathlib import Path


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


def test_dry_run_skip_health_outputs_skip_message(repo_copy: Path) -> None:
    result = run_deploy(repo_copy, "core", "--dry-run", "--skip-health")

    assert result.returncode == 0, result.stderr
    assert "Health check automático ignorado (flag --skip-health)." in result.stdout


def test_missing_local_env_file_fails(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    local_env.unlink()

    result = run_deploy(repo_copy, "core", "--dry-run")

    assert result.returncode == 1
    assert "Arquivo env/local/core.env não encontrado" in result.stderr
    assert "Copie o template padrão" in result.stderr


def test_deploy_without_privileges_skips_chown(repo_copy: Path) -> None:
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

    fake_docker = fake_bin / "docker"
    fake_docker.write_text(
        "#!/usr/bin/env bash\n"
        "exit 0\n",
        encoding="utf-8",
    )
    fake_docker.chmod(0o755)

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

    for directory in (repo_copy / "data", repo_copy / "backups"):
        assert directory.exists()


def test_deploy_creates_custom_data_dir(repo_copy: Path) -> None:
    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        "TZ=UTC\n"
        "APP_SECRET=test-secret-abcdef0123456789\n"
        "APP_RETENTION_HOURS=12\n"
        "SERVICE_NAME=app-core\n"
        "APP_DATA_DIR=custom-storage\n"
        "APP_DATA_UID=2000\n"
        "APP_DATA_GID=3000\n",
        encoding="utf-8",
    )

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

    fake_docker = fake_bin / "docker"
    fake_docker.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    fake_docker.chmod(0o755)

    env_overrides = {"PATH": f"{fake_bin}:{os.environ['PATH']}", "CI": "1"}

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
    assert (repo_copy / "custom-storage").exists()
    assert (repo_copy / "backups").exists()
