from __future__ import annotations

import base64
import json
import os
from pathlib import Path

import pytest

from tests.conftest import DockerStub

from .utils import run_check_health


@pytest.mark.usefixtures("docker_stub")
def test_json_output_structure(docker_stub: DockerStub) -> None:
    path_entries = os.environ.get("PATH", "").split(os.pathsep)
    assert path_entries, "PATH is expected to include the Docker stub directory"
    stub_dir = Path(path_entries[0])
    stub_binary = stub_dir / "docker"
    assert stub_binary.exists(), "Docker stub binary is required for the test"

    stub_source = stub_binary.read_text(encoding="utf-8")
    hook_snippet = "log_override_key = f\"DOCKER_STUB_LOG_CONTENT_{service}\""
    if hook_snippet not in stub_source:
        replacement_target = "        else:\n            exit_code = base_exit_code\n"
        insertion = """
    if service:
        log_override_key = f"DOCKER_STUB_LOG_CONTENT_{service}"
        log_override = os.environ.get(log_override_key)
        if log_override:
            print(log_override)
"""
        if replacement_target not in stub_source:
            raise AssertionError("Stub structure has changed; update the test hook.")
        stub_source = stub_source.replace(replacement_target, replacement_target + insertion)
        stub_binary.write_text(stub_source, encoding="utf-8")

    env = {
        "HEALTH_SERVICES": "app svc-failure",
        "DOCKER_STUB_SERVICES_OUTPUT": "app\nsvc-failure",
        "DOCKER_STUB_FAIL_ALWAYS_FOR": "svc-failure",
        "DOCKER_STUB_LOG_CONTENT_app": "Simulated log entry for app",
    }

    result = run_check_health(["--format", "json", "core"], env=env)

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)

    assert payload["format"] == "json"
    assert payload["status"] == "degraded"
    assert payload["instance"] == "core"

    targets = payload["targets"]
    assert targets["requested"] == ["app", "svc-failure"]
    assert targets["automatic"] == []
    assert targets["all"] == ["app", "svc-failure"]

    logs = payload["logs"]
    assert logs["failed"] == ["svc-failure"]
    assert logs["has_success"] is True
    assert logs["total"] == 2
    assert logs["successful"] == 1
    assert len(logs["entries"]) == 2

    entries = {entry["service"]: entry for entry in logs["entries"]}
    assert set(entries) == {"app", "svc-failure"}

    app_entry = entries["app"]
    assert app_entry["status"] == "ok"
    assert app_entry["log"] == "Simulated log entry for app"
    assert app_entry["log_b64"] == base64.b64encode(app_entry["log"].encode()).decode()

    failure_entry = entries["svc-failure"]
    assert failure_entry["status"] == "error"
    assert failure_entry["log"] == ""
    assert "log_b64" not in failure_entry

    compose_section = payload["compose"]
    assert "raw" in compose_section
    assert "parsed" not in compose_section
    assert "parsed_error" not in compose_section
