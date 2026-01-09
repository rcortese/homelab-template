from __future__ import annotations

import subprocess
import pytest

from .utils import REPO_ROOT, SCRIPT_PATH


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_help_option_displays_usage_and_exits_successfully(flag: str) -> None:
    result = subprocess.run(
        [str(SCRIPT_PATH), flag],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert result.returncode == 0
    assert "Usage: scripts/validate_compose.sh" in result.stdout
    assert result.stderr == ""
