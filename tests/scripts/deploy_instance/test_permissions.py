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
        "Desired owner 1000:1000 not applied (insufficient permissions)."
        in result.stdout
    )

    for directory in (
        (repo_copy / "data" / "core" / "app").resolve(),
        (repo_copy / "backups").resolve(),
    ):
        assert Path(directory).exists()


def test_deploy_rejects_repo_root_override(repo_copy: Path) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    core_env.write_text("REPO_ROOT=/tmp/override\n", encoding="utf-8")

    result = run_deploy(
        repo_copy,
        "core",
        "--skip-structure",
        "--skip-validate",
        "--skip-health",
        "--force",
        env_overrides={"CI": "1"},
    )

    assert result.returncode != 0
    assert "REPO_ROOT must not be set in env files" in result.stderr


def test_deploy_rejects_legacy_app_data_dir(repo_copy: Path) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR=custom-storage\n",
        encoding="utf-8",
    )

    result = run_deploy(
        repo_copy,
        "core",
        "--skip-structure",
        "--skip-validate",
        "--skip-health",
        "--force",
        env_overrides={"CI": "1"},
    )

    assert result.returncode != 0
    assert "APP_DATA_DIR and APP_DATA_DIR_MOUNT are no longer supported" in result.stderr
