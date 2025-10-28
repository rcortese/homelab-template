from __future__ import annotations

import json
import os
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

from .utils import run_compose

if TYPE_CHECKING:
    from ..conftest import DockerStub


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
""",
        encoding="utf-8",
    )
    stub_path.chmod(0o755)

    original_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{original_path}")
    monkeypatch.setenv("CUSTOM_COMPOSE_LOG", str(log_path))

    result = run_compose(args=["--", "ps"], env={"DOCKER_COMPOSE_BIN": "custom-compose"})

    assert result.returncode == 0, result.stderr

    entries = [
        json.loads(line)
        for line in log_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert len(entries) == 1
    entry = entries[0]
    assert entry["executable"] == "custom-compose"
    assert entry["args"] == ["ps"]


def test_fallback_to_docker_compose(docker_stub: DockerStub) -> None:
    result = run_compose(args=["--", "ps"])

    assert result.returncode == 0
    assert docker_stub.read_calls() == [["compose", "ps"]]


def test_respects_multi_word_docker_compose_bin(docker_stub: DockerStub) -> None:
    result = run_compose(
        args=["--", "ps"],
        env={"DOCKER_COMPOSE_BIN": "docker --context remote compose"},
    )

    assert result.returncode == 0
    assert docker_stub.read_calls() == [["--context", "remote", "compose", "ps"]]
