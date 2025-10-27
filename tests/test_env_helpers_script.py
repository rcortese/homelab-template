import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts" / "lib" / "env_helpers.sh"


def run_normalization(base_input: str, mount_input: str) -> subprocess.CompletedProcess[str]:
    command = (
        f"source '{SCRIPT_PATH}' && "
        "base='' mount='' && "
        "normalize_app_data_dir_inputs "
        f"'{REPO_ROOT}' 'app' \"$1\" \"$2\" base mount && "
        "printf '%s\\n%s\\n' \"$base\" \"$mount\""
    )
    return subprocess.run(
        ["bash", "-c", command, "bash", base_input, mount_input],
        check=False,
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize(
    "base_input,mount_input,expected_base,expected_mount",
    [
        ("", "", "", ""),
        (
            "data/app-core",
            "",
            "data/app-core",
            str((REPO_ROOT / "data" / "app-core" / "app").resolve()),
        ),
        (
            "./data/app-core/",
            "",
            "data/app-core",
            str((REPO_ROOT / "data" / "app-core" / "app").resolve()),
        ),
        (
            str((REPO_ROOT / "absolute-storage").resolve()),
            "",
            str((REPO_ROOT / "absolute-storage").resolve()),
            str((REPO_ROOT / "absolute-storage" / "app").resolve()),
        ),
        (
            "",
            "custom-storage",
            "custom-storage",
            str((REPO_ROOT / "custom-storage" / "app").resolve()),
        ),
        (
            "",
            str((REPO_ROOT / "external" / "app").resolve()),
            "external",
            str((REPO_ROOT / "external" / "app").resolve()),
        ),
        (
            "",
            "../shared/data",
            str((REPO_ROOT / "../shared/data").resolve()),
            str((REPO_ROOT / "../shared/data" / "app").resolve()),
        ),
    ],
)
def test_normalize_app_data_dir_inputs_outputs_expected_paths(
    base_input: str, mount_input: str, expected_base: str, expected_mount: str
) -> None:
    result = run_normalization(base_input, mount_input)

    assert result.returncode == 0
    base, mount = result.stdout.splitlines()
    assert base == expected_base
    assert mount == expected_mount


def test_normalize_app_data_dir_inputs_rejects_conflicting_inputs() -> None:
    command = (
        f"source '{SCRIPT_PATH}' && "
        "base='' mount='' && "
        "normalize_app_data_dir_inputs "
        f"'{REPO_ROOT}' 'app' \"$1\" \"$2\" base mount"
    )
    result = subprocess.run(
        [
            "bash",
            "-c",
            command,
            "bash",
            "data/app-core",
            "custom-storage",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert "APP_DATA_DIR e APP_DATA_DIR_MOUNT" in result.stderr
