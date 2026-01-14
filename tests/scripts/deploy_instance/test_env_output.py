from pathlib import Path

from .utils import run_deploy


def test_deploy_writes_consolidated_env(repo_copy: Path, docker_stub: object) -> None:
    result = run_deploy(
        repo_copy,
        "core",
        "--skip-structure",
        "--skip-validate",
        "--skip-health",
        env_overrides={"CI": "1"},
    )

    assert result.returncode == 0, result.stderr

    env_path = repo_copy / ".env"
    assert env_path.exists()
    env_contents = env_path.read_text(encoding="utf-8")
    assert f"REPO_ROOT={repo_copy}" in env_contents
    assert "LOCAL_INSTANCE=core" in env_contents
