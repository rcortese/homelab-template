from __future__ import annotations

import os
import subprocess
from pathlib import Path


def run_backup(
    repo_copy: Path, instance: str, *args: str, env_overrides: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    command = [str(repo_copy / "scripts" / "backup.sh"), instance, *args]
    env = {**os.environ, "BACKUP_INSTANCE": instance}
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
