from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_compose.sh"
BASE_COMPOSE = REPO_ROOT / "compose" / "base.yml"
APP_BASE_COMPOSE = REPO_ROOT / "compose" / "apps" / "app" / "base.yml"
CORE_COMPOSE = REPO_ROOT / "compose" / "apps" / "app" / "core.yml"
MEDIA_COMPOSE = REPO_ROOT / "compose" / "apps" / "app" / "media.yml"
CORE_ENV = REPO_ROOT / "env" / "core.example.env"
MEDIA_ENV = REPO_ROOT / "env" / "media.example.env"
CORE_ENV_LOCAL = REPO_ROOT / "env" / "local" / "core.env"
MEDIA_ENV_LOCAL = REPO_ROOT / "env" / "local" / "media.env"


def run_validate_compose(env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env={**os.environ, **env},
    )


def expected_compose_call(env_file: Path, files: list[Path], *args: str) -> list[str]:
    cmd: list[str] = ["compose", "--env-file", str(env_file)]
    for file in files:
        cmd.extend(["-f", str(file)])
    cmd.extend(args)
    return cmd


__all__ = [
    "APP_BASE_COMPOSE",
    "BASE_COMPOSE",
    "CORE_COMPOSE",
    "CORE_ENV",
    "CORE_ENV_LOCAL",
    "MEDIA_COMPOSE",
    "MEDIA_ENV",
    "MEDIA_ENV_LOCAL",
    "REPO_ROOT",
    "SCRIPT_PATH",
    "expected_compose_call",
    "run_validate_compose",
]
