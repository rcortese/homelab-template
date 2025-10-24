from __future__ import annotations

import json
import os
import shutil
from collections.abc import Iterable
from pathlib import Path

import pytest


class DockerStub:
    def __init__(self, log_path: Path, exit_code_file: Path):
        self._log_path = log_path
        self._exit_code_file = exit_code_file

    def set_exit_code(self, code: int) -> None:
        self._exit_code_file.write_text(str(code))

    def read_calls(self) -> list[list[str]]:
        if not self._log_path.exists():
            return []
        lines = [line.strip() for line in self._log_path.read_text().splitlines() if line.strip()]
        return [json.loads(line) for line in lines]


@pytest.fixture
def docker_stub(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> DockerStub:
    bin_dir = tmp_path / "docker-bin"
    bin_dir.mkdir()
    log_path = tmp_path / "docker_stub_calls.log"
    exit_code_file = tmp_path / "docker_stub_exit_code"
    exit_code_file.write_text("0")

    stub_path = bin_dir / "docker"
    stub_path.write_text(
        """#!/usr/bin/env python3
import json
import os
import pathlib
import sys

log_path = pathlib.Path(os.environ[\"DOCKER_STUB_LOG\"])
with log_path.open(\"a\", encoding=\"utf-8\") as handle:
    json.dump(sys.argv[1:], handle)
    handle.write(\"\\n\")

exit_code_file = os.environ.get(\"DOCKER_STUB_EXIT_CODE_FILE\")
exit_code = 0
if exit_code_file:
    try:
        exit_code = int(pathlib.Path(exit_code_file).read_text().strip() or \"0\")
    except FileNotFoundError:
        exit_code = 0

sys.exit(exit_code)
"""
    )
    stub_path.chmod(0o755)

    original_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{original_path}")
    monkeypatch.setenv("DOCKER_STUB_LOG", str(log_path))
    monkeypatch.setenv("DOCKER_STUB_EXIT_CODE_FILE", str(exit_code_file))

    return DockerStub(log_path=log_path, exit_code_file=exit_code_file)


REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def repo_copy_additional_dirs() -> tuple[str, ...]:
    return ()


@pytest.fixture
def repo_copy(
    tmp_path: Path,
    request: pytest.FixtureRequest,
    repo_copy_additional_dirs: Iterable[str],
) -> Path:
    copy_root = tmp_path / "repo"

    default_dirs: tuple[str, ...] = ("scripts", "compose", "env")
    requested_dirs: list[str] = list(default_dirs)

    # Allow indirect parametrization of the fixture
    if hasattr(request, "param") and request.param is not None:
        params = request.param
        if isinstance(params, str):
            requested_dirs.append(params)
        else:
            requested_dirs.extend(params)

    requested_dirs.extend(repo_copy_additional_dirs)

    # Deduplicate while preserving order
    seen: set[str] = set()
    directories_to_copy: list[str] = []
    for folder in requested_dirs:
        if folder not in seen:
            seen.add(folder)
            directories_to_copy.append(folder)

    for folder in directories_to_copy:
        source = REPO_ROOT / folder
        destination = copy_root / folder

        if source.exists():
            shutil.copytree(source, destination)
        else:
            destination.mkdir(parents=True, exist_ok=True)

    local_env_dir = copy_root / "env" / "local"
    local_env_dir.mkdir(parents=True, exist_ok=True)
    (local_env_dir / "core.env").write_text(
        "TZ=UTC\n"
        "APP_SECRET=test-secret-1234567890123456\n"
        "APP_RETENTION_HOURS=24\n"
        "SERVICE_NAME=app-core\n"
        "APP_DATA_DIR=data\n",
        encoding="utf-8",
    )

    return copy_root
