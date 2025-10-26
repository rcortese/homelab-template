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


def test_respects_multi_word_docker_compose_bin(docker_stub: DockerStub) -> None:
    result = run_compose(
        args=["--", "ps"],
        env={"DOCKER_COMPOSE_BIN": "docker --context remote compose"},
    )

    assert result.returncode == 0
    assert docker_stub.read_calls() == [["--context", "remote", "compose", "ps"]]


def test_instance_uses_expected_env_and_compose_files(
    repo_copy: Path, docker_stub: DockerStub
) -> None:
    result = run_compose_in_repo(repo_copy, args=["core"])

    assert result.returncode == 0

    calls = docker_stub.read_calls()
    assert len(calls) == 1
    command = calls[0]

    assert "--env-file" in command
    env_arg_index = command.index("--env-file")
    assert command[env_arg_index + 1] == "env/local/core.env"

    compose_files = [
        command[index + 1]
        for index, arg in enumerate(command)
        if arg == "-f"
    ]
    assert compose_files == [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
    ]


def test_unknown_instance_returns_error(repo_copy: Path) -> None:
    result = run_compose_in_repo(repo_copy, args=["unknown"])

    assert result.returncode == 1
    assert "instância desconhecida 'unknown'" in result.stderr
    assert "Disponíveis:" in result.stderr
    assert "core" in result.stderr
    assert "media" in result.stderr
