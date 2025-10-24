from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest


if TYPE_CHECKING:
    from .conftest import DockerStub


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "compose.sh"


def run_compose(
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(SCRIPT_PATH)]
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


def test_requires_arguments() -> None:
    result = run_compose()

    assert result.returncode == 1
    assert "Uso:" in result.stdout


def test_respects_docker_compose_bin(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_path = tmp_path / "custom_compose_log.jsonl"

    stub_path = bin_dir / "custom-compose"
    stub_path.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

log_path = Path(os.environ[\"CUSTOM_COMPOSE_LOG\"])
with log_path.open(\"a\", encoding=\"utf-8\") as handle:
    json.dump({
        \"executable\": Path(sys.argv[0]).name,
        \"args\": sys.argv[1:],
    }, handle)
    handle.write(\"\\n\")

sys.exit(0)
"""
    )
    stub_path.chmod(0o755)

    original_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{original_path}")
    monkeypatch.setenv("CUSTOM_COMPOSE_LOG", str(log_path))

    result = run_compose(args=["--", "ps"], env={"DOCKER_COMPOSE_BIN": "custom-compose"})

    assert result.returncode == 0, result.stderr

    entries = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
    assert len(entries) == 1
    entry = entries[0]
    assert entry["executable"] == "custom-compose"
    assert entry["args"] == ["ps"]


def test_fallback_to_docker_compose(docker_stub: DockerStub) -> None:
    result = run_compose(args=["--", "ps"])

    assert result.returncode == 0
    assert docker_stub.read_calls() == [["compose", "ps"]]
