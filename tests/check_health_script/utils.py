from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from tests.conftest import DockerStub  # noqa: F401


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_health.sh"


def run_check_health(
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    script_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(script_path or SCRIPT_PATH)]
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


def _expected_compose_call(env_file: str | None, files: list[str], *args: str) -> list[str]:
    cmd = ["compose"]
    if env_file:
        cmd.extend(["--env-file", env_file])
    for path in files:
        cmd.extend(["-f", path])
    cmd.extend(args)
    return cmd
