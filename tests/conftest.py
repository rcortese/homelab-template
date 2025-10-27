from __future__ import annotations

import json
import os
import shutil
from collections.abc import Iterable
from pathlib import Path

import pytest


class DockerStub:
    def __init__(self, log_path: Path, exit_code_file: Path, fail_once_state: Path):
        self._log_path = log_path
        self._exit_code_file = exit_code_file
        self._fail_once_state = fail_once_state

    def set_exit_code(self, code: int) -> None:
        self._exit_code_file.write_text(str(code))

    def _read_raw_records(self) -> list[object]:
        if not self._log_path.exists():
            return []
        lines = [line.strip() for line in self._log_path.read_text().splitlines() if line.strip()]
        return [json.loads(line) for line in lines]

    def read_calls(self) -> list[list[str]]:
        records = self._read_raw_records()
        result: list[list[str]] = []
        for record in records:
            if isinstance(record, dict) and "args" in record:
                value = record.get("args")
                if isinstance(value, list):
                    result.append([str(item) for item in value])
                    continue
            if isinstance(record, list):
                result.append([str(item) for item in record])
            else:
                result.append([])
        return result

    def read_call_env(self) -> list[dict[str, str]]:
        records = self._read_raw_records()
        environments: list[dict[str, str]] = []
        for record in records:
            if isinstance(record, dict):
                env_data = record.get("env")
                if isinstance(env_data, dict):
                    environments.append({str(key): str(value) for key, value in env_data.items() if value is not None})
                    continue
            environments.append({})
        return environments

    @property
    def fail_once_state(self) -> Path:
        return self._fail_once_state

    def reset_fail_once_state(self) -> None:
        if self._fail_once_state.exists():
            self._fail_once_state.unlink()


@pytest.fixture
def docker_stub(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> DockerStub:
    bin_dir = tmp_path / "docker-bin"
    bin_dir.mkdir()
    log_path = tmp_path / "docker_stub_calls.log"
    exit_code_file = tmp_path / "docker_stub_exit_code"
    exit_code_file.write_text("0")
    fail_once_state = tmp_path / "docker_stub_fail_once_state"

    stub_path = bin_dir / "docker"
    stub_path.write_text(
        """#!/usr/bin/env python3
import json
import os
import pathlib
import sys

log_path = pathlib.Path(os.environ[\"DOCKER_STUB_LOG\"])
app_data_dir_mount = os.environ.get(\"APP_DATA_DIR_MOUNT\")
absolute_mount = None
if app_data_dir_mount:
    absolute_mount = os.path.abspath(app_data_dir_mount)
record = {
    \"args\": sys.argv[1:],
    \"env\": {
        \"APP_DATA_DIR\": os.environ.get(\"APP_DATA_DIR\"),
        \"APP_DATA_DIR_MOUNT\": os.environ.get(\"APP_DATA_DIR_MOUNT\"),
        \"APP_DATA_DIR_MOUNT_ABS\": absolute_mount,
    },
}
with log_path.open(\"a\", encoding=\"utf-8\") as handle:
    json.dump(record, handle)
    handle.write(\"\\n\")

args = sys.argv[1:]

if \"config\" in args and \"--services\" in args:
    services_output = os.environ.get(\"DOCKER_STUB_SERVICES_OUTPUT\", \"app\")
    if services_output:
        print(services_output)

exit_code_file = os.environ.get(\"DOCKER_STUB_EXIT_CODE_FILE\")
base_exit_code = 0
if exit_code_file:
    try:
        base_exit_code = int(pathlib.Path(exit_code_file).read_text().strip() or \"0\")
    except FileNotFoundError:
        base_exit_code = 0

exit_code = base_exit_code

always_fail_logs = os.environ.get(\"DOCKER_STUB_ALWAYS_FAIL_LOGS\")
fail_always_for = {
    entry.strip()
    for entry in os.environ.get(\"DOCKER_STUB_FAIL_ALWAYS_FOR\", \"\").split(\",\")
    if entry.strip()
}
fail_once_for = {
    entry.strip()
    for entry in os.environ.get(\"DOCKER_STUB_FAIL_ONCE_FOR\", \"\").split(\",\")
    if entry.strip()
}
state_file = os.environ.get(\"DOCKER_STUB_FAIL_ONCE_STATE\")

if \"logs\" in args:
    service = args[-1] if args else None
    if always_fail_logs:
        exit_code = 1
    elif service and service in fail_always_for:
        exit_code = 1
    elif service and service in fail_once_for and state_file:
        state_path = pathlib.Path(state_file)
        if state_path.exists():
            already = {
                entry
                for entry in state_path.read_text(encoding=\"utf-8\").split(\",\")
                if entry
            }
        else:
            already = set()
        if service not in already:
            already.add(service)
            state_path.write_text(\",\".join(sorted(already)), encoding=\"utf-8\")
            exit_code = 1
        else:
            exit_code = base_exit_code

sys.exit(exit_code)
""",
        encoding="utf-8",
    )
    stub_path.chmod(0o755)
    
    original_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{original_path}")
    monkeypatch.setenv("DOCKER_STUB_LOG", str(log_path))
    monkeypatch.setenv("DOCKER_STUB_EXIT_CODE_FILE", str(exit_code_file))
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_STATE", str(fail_once_state))

    return DockerStub(log_path=log_path, exit_code_file=exit_code_file, fail_once_state=fail_once_state)


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
    (local_env_dir / "common.env").write_text(
        "TZ=UTC\n"
        "APP_SECRET=test-secret-1234567890123456\n"
        "APP_RETENTION_HOURS=24\n"
        "APP_DATA_UID=1000\n"
        "APP_DATA_GID=1000\n",
        encoding="utf-8",
    )

    (local_env_dir / "core.env").write_text("", encoding="utf-8")

    override_only_dir = copy_root / "compose" / "apps" / "overrideonly"
    override_only_dir.mkdir(parents=True, exist_ok=True)
    (override_only_dir / "core.yml").write_text(
        "services:\n"
        "  overrideonly:\n"
        "    image: alpine:3.18\n"
        "    command:\n"
        "      - sleep\n"
        "      - infinity\n",
        encoding="utf-8",
    )

    return copy_root
