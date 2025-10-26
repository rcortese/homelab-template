import os
from pathlib import Path

from .utils import run_deploy


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

    for directory in (repo_copy / "data" / "app-core", repo_copy / "backups"):
        assert directory.exists()


def test_deploy_uses_convention_for_data_dir(repo_copy: Path) -> None:
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
    data_dir = repo_copy / "data" / "app-core"
    assert data_dir.exists()
    assert not (repo_copy / "custom-storage").exists()
    assert (repo_copy / "backups").exists()
