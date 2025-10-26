from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "compose.sh"


def run_compose(
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    script_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    target_script = script_path or SCRIPT_PATH
    command = [str(target_script)]
    if args:
        command.extend(args)
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env={**os.environ, **(env or {})},
    )


def run_compose_in_repo(
    repo_root: Path,
    *,
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return run_compose(
        args=args,
        env=env,
        cwd=repo_root,
        script_path=repo_root / "scripts" / "compose.sh",
    )
