from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from tests.conftest import DockerStub  # noqa: F401

from tests.helpers.compose_instances import load_compose_instances_data


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_health.sh"
COMPOSE_INSTANCES_DATA = load_compose_instances_data(REPO_ROOT)


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
    env_files: str | Iterable[str] | None,
    files: Iterable[str],
    *args: str,
    base_cmd: list[str] | None = None,
) -> list[str]:
    cmd = list(base_cmd or ["compose"])
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


def expected_consolidated_plan_calls(
    env_files: str | Iterable[str] | None,
    files: Iterable[str],
    output_file: Path,
    base_cmd: list[str] | None = None,
) -> list[list[str]]:
    plan_files = list(files)
    return [
        _expected_compose_call(
            env_files,
            plan_files,
            "config",
            "--output",
            str(output_file),
            base_cmd=base_cmd,
        ),
        _expected_compose_call(
            env_files,
            [*plan_files, output_file],
            "config",
            "-q",
            base_cmd=base_cmd,
        ),
    ]


def expected_plan_for_instance(instance: str) -> list[str]:
    return COMPOSE_INSTANCES_DATA.compose_plan(instance)


def expected_env_for_instance(instance: str) -> list[str]:
    return COMPOSE_INSTANCES_DATA.env_files_map.get(instance, [])
