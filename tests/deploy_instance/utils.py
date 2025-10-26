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


def _extract_compose_files(stdout: str) -> list[str]:
    for line in stdout.splitlines():
        if line.startswith("[*] COMPOSE_FILES="):
            return line.split("=", 1)[1].split()
    raise AssertionError(f"COMPOSE_FILES not found in output: {stdout!r}")
