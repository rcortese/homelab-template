import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = REPO_ROOT / "scripts" / "lib" / "env_helpers.sh"


@pytest.mark.parametrize(
    "input_value,expected",
    [
        ("", ""),
        ("data", "../data"),
        ("./data", "../data"),
        ("../data", "../data"),
        ("../../nested/data", "../../nested/data"),
    ],
)
def test_resolve_app_data_dir_mount_handles_relative_paths(input_value, expected):
    command = f"source '{SCRIPT_PATH}' && resolve_app_data_dir_mount \"$1\""
    result = subprocess.run(
        ["bash", "-c", command, "bash", input_value],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0
    assert result.stdout == expected
