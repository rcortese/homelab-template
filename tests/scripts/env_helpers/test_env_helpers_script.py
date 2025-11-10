import os
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "lib" / "env_helpers.sh"


def _run_derive(
    *,
    repo_root: Path,
    service_slug: str,
    default_rel: str,
    app_dir: str,
    app_mount: str,
) -> subprocess.CompletedProcess[str]:
    script = f"""
set -euo pipefail
source '{SCRIPT_PATH}'
declare output_dir=""
declare output_mount=""
if env_helpers__derive_app_data_paths "$REPO_ROOT" "$SERVICE_SLUG" "$DEFAULT_REL" "$APP_DIR" "$APP_MOUNT" output_dir output_mount; then
  printf '%s\n%s\n' "$output_dir" "$output_mount"
else
  exit 42
fi
"""

    env = os.environ.copy()
    env.update(
        {
            "REPO_ROOT": str(repo_root),
            "SERVICE_SLUG": service_slug,
            "DEFAULT_REL": default_rel,
            "APP_DIR": app_dir,
            "APP_MOUNT": app_mount,
        }
    )

    return subprocess.run(
        ["bash", "-c", script],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def _run_normalize_absolute(*, repo_root: Path, value: str) -> subprocess.CompletedProcess[str]:
    script = f"""
set -euo pipefail
source '{SCRIPT_PATH}'
env_helpers__normalize_absolute_path "$REPO_ROOT" "$VALUE"
"""

    env = os.environ.copy()
    env.update({"REPO_ROOT": str(repo_root), "VALUE": value})

    return subprocess.run(
        ["bash", "-c", script],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def test_derive_from_relative_app_dir() -> None:
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir="custom/storage",
        app_mount="",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines == ["custom/storage", f"{REPO_ROOT}/custom/storage/app"]


def test_derive_from_default_when_app_dir_blank() -> None:
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir="",
        app_mount="",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines == ["data/core/app", f"{REPO_ROOT}/data/core/app"]


def test_derive_normalizes_absolute_app_dir() -> None:
    absolute_dir = (REPO_ROOT / "absolute" / "storage").as_posix()
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir=absolute_dir,
        app_mount="",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines == ["absolute/storage", f"{REPO_ROOT}/absolute/storage/app"]


def test_derive_from_relative_mount_path() -> None:
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir="",
        app_mount="custom-mount",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines == ["custom-mount", f"{REPO_ROOT}/custom-mount/app"]


def test_derive_from_external_mount_keeps_default_rel() -> None:
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir="",
        app_mount="/srv/external",
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines == ["data/core/app", "/srv/external/app"]


def test_derive_rejects_conflicting_inputs() -> None:
    result = _run_derive(
        repo_root=REPO_ROOT,
        service_slug="app",
        default_rel="data/core/app",
        app_dir="custom/storage",
        app_mount="/srv/custom",
    )

    assert result.returncode == 42
    assert "APP_DATA_DIR and APP_DATA_DIR_MOUNT" in result.stderr


def test_normalize_absolute_path_from_relative() -> None:
    result = _run_normalize_absolute(
        repo_root=REPO_ROOT,
        value="data/core/app",
    )

    assert result.returncode == 0, result.stderr
    expected = (REPO_ROOT / "data" / "core" / "app").as_posix()
    assert result.stdout.strip() == expected


def test_normalize_absolute_path_preserves_absolute_value() -> None:
    input_path = "/srv/external/storage"
    result = _run_normalize_absolute(
        repo_root=REPO_ROOT,
        value=input_path,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == input_path
