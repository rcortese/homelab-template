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

    for directory in (
        (repo_copy / "data" / "app-core" / "app-core").resolve(),
        (repo_copy / "backups").resolve(),
    ):
        assert Path(directory).exists()


def test_deploy_uses_convention_for_data_dir(repo_copy: Path) -> None:
    common_env = repo_copy / "env" / "local" / "common.env"
    common_env.write_text(
        "TZ=UTC\n"
        "APP_SECRET=test-secret-abcdef0123456789\n"
        "APP_RETENTION_HOURS=12\n"
        "APP_DATA_UID=2000\n"
        "APP_DATA_GID=3000\n",
        encoding="utf-8",
    )

    core_env = repo_copy / "env" / "local" / "core.env"
    core_env.write_text(
        "APP_DATA_DIR=custom-storage\n",
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
    data_dir = (repo_copy / "custom-storage").resolve()
    mount_dir = data_dir / "app-core"
    assert data_dir.exists()
    assert mount_dir.exists()
    assert not (repo_copy / "data" / "app-core").exists()
    assert (repo_copy / "backups").exists()


def test_deploy_with_absolute_data_dir(repo_copy: Path, docker_stub) -> None:
    absolute_data_dir = (repo_copy / "absolute-storage").resolve()

    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR={absolute_data_dir}\n",
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

    assert result.returncode == 0, result.stderr

    assert absolute_data_dir.exists()
    assert (absolute_data_dir / "app-core").exists()
    assert (repo_copy / "backups").exists()

    env_records = docker_stub.read_call_env()
    assert len(env_records) >= 1
    expected_relative = absolute_data_dir.relative_to(repo_copy.resolve()).as_posix()
    assert env_records[0].get("APP_DATA_DIR") == expected_relative
    mount_value = env_records[0].get("APP_DATA_DIR_MOUNT")
    assert mount_value is not None
    mount_path = Path(mount_value)
    assert mount_path.is_absolute()
    assert mount_path == absolute_data_dir / "app-core"


def test_deploy_with_empty_app_data_dir_uses_default(
    repo_copy: Path, docker_stub
) -> None:
    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR=\n",
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

    assert result.returncode == 0, result.stderr
    base_dir = (repo_copy / "data" / "app-core").resolve()
    mount_dir = base_dir / "app-core"
    assert base_dir.exists()
    assert mount_dir.exists()
    assert (repo_copy / "backups").exists()

    env_records = docker_stub.read_call_env()
    assert len(env_records) >= 1
    assert env_records[0].get("APP_DATA_DIR") == "data/app-core"
    mount_value = env_records[0].get("APP_DATA_DIR_MOUNT")
    assert mount_value is not None
    mount_path = Path(mount_value)
    assert mount_path.is_absolute()
    assert mount_path == mount_dir.resolve()


def test_deploy_with_only_mount_defined(repo_copy: Path, docker_stub) -> None:
    mount_base = (repo_copy / "external-storage").resolve()

    core_env = repo_copy / "env" / "local" / "core.env"
    existing_content = core_env.read_text(encoding="utf-8")
    core_env.write_text(
        f"{existing_content}APP_DATA_DIR_MOUNT={mount_base}\n",
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

    assert result.returncode == 0, result.stderr

    mount_dir = mount_base / "app-core"
    assert mount_dir.exists()
    assert (repo_copy / "backups").exists()

    env_records = docker_stub.read_call_env()
    assert len(env_records) >= 1
    expected_relative = mount_base.relative_to(repo_copy.resolve()).as_posix()
    assert env_records[0].get("APP_DATA_DIR") == expected_relative
    mount_value = env_records[0].get("APP_DATA_DIR_MOUNT")
    assert mount_value is not None
    mount_path = Path(mount_value)
    assert mount_path.is_absolute()
    assert mount_path == mount_dir
