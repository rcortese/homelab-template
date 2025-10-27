from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from .utils import expected_compose_call

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_prefers_local_env_when_available(repo_copy: Path, docker_stub: DockerStub) -> None:
    docker_stub.set_exit_code(0)

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "core"},
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        [
            repo_copy / "env" / "local" / "common.env",
            repo_copy / "env" / "local" / "core.env",
        ],
        [
            repo_copy / "compose" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "core.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "base.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "core.yml",
            repo_copy / "compose" / "apps" / "overrideonly" / "core.yml",
            repo_copy / "compose" / "apps" / "worker" / "base.yml",
            repo_copy / "compose" / "apps" / "worker" / "core.yml",
            repo_copy / "compose" / "apps" / "baseonly" / "base.yml",
        ],
        "config",
    )


def test_includes_extra_files_from_env_file(repo_copy: Path, docker_stub: DockerStub) -> None:
    docker_stub.set_exit_code(0)

    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    extra_files = ["metrics.yml", "logging.yml"]
    for name in extra_files:
        (overlay_dir / name).write_text(
            "version: '3.9'\nservices:\n  placeholder:\n    image: busybox:latest\n",
            encoding="utf-8",
        )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml compose/overlays/logging.yml\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "core"},
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        [
            repo_copy / "env" / "local" / "common.env",
            repo_copy / "env" / "local" / "core.env",
        ],
        [
            repo_copy / "compose" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "core.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "base.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "core.yml",
            repo_copy / "compose" / "apps" / "overrideonly" / "core.yml",
            repo_copy / "compose" / "apps" / "worker" / "base.yml",
            repo_copy / "compose" / "apps" / "worker" / "core.yml",
            repo_copy / "compose" / "apps" / "baseonly" / "base.yml",
            repo_copy / "compose" / "overlays" / "metrics.yml",
            repo_copy / "compose" / "overlays" / "logging.yml",
        ],
        "config",
    )


def test_env_override_for_extra_files(repo_copy: Path, docker_stub: DockerStub) -> None:
    docker_stub.set_exit_code(0)

    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    (overlay_dir / "custom.yml").write_text(
        "version: '3.9'\nservices:\n  custom:\n    image: busybox:latest\n",
        encoding="utf-8",
    )
    (overlay_dir / "metrics.yml").write_text(
        "version: '3.9'\nservices:\n  metrics:\n    image: busybox:latest\n",
        encoding="utf-8",
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={
            **os.environ,
            "COMPOSE_INSTANCES": "core",
            "COMPOSE_EXTRA_FILES": "compose/overlays/custom.yml",
        },
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        [
            repo_copy / "env" / "local" / "common.env",
            repo_copy / "env" / "local" / "core.env",
        ],
        [
            repo_copy / "compose" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "base.yml",
            repo_copy / "compose" / "apps" / "app" / "core.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "base.yml",
            repo_copy / "compose" / "apps" / "monitoring" / "core.yml",
            repo_copy / "compose" / "apps" / "overrideonly" / "core.yml",
            repo_copy / "compose" / "apps" / "worker" / "base.yml",
            repo_copy / "compose" / "apps" / "worker" / "core.yml",
            repo_copy / "compose" / "apps" / "baseonly" / "base.yml",
            repo_copy / "compose" / "overlays" / "custom.yml",
        ],
        "config",
    )
