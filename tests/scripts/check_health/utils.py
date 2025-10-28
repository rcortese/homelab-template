from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from tests.conftest import DockerStub  # noqa: F401


REPO_ROOT = Path(__file__).resolve().parents[3]
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


from typing import Iterable


def _expected_compose_call(
    env_files: str | Iterable[str] | None, files: Iterable[str], *args: str
) -> list[str]:
    cmd = ["compose"]
    if env_files:
        if isinstance(env_files, str):
            env_entries = [env_files]
        else:
            env_entries = list(env_files)
        for env_file in env_entries:
            cmd.extend(["--env-file", str(env_file)])
    for path in files:
        cmd.extend(["-f", str(path)])
    cmd.extend(args)
    return cmd
