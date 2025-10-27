from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "lib" / "env_loader.sh"


def run_env_loader(
    env_file: Path | None = None,
    keys: list[str] | None = None,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(SCRIPT_PATH)]
    if env_file is not None:
        command.append(str(env_file))
    if keys:
        command.extend(keys)
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env=os.environ.copy(),
    )


def test_env_loader_parses_various_formats(tmp_path: Path) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            [
                "# initial comment",
                "export FOO=bar",
                'BAR="quoted value"',
                "BAZ=value with spaces # inline comment",
                "EMPTY=",
                "",
                "# trailing comment",
            ]
        ),
        encoding="utf-8",
    )

    result = run_env_loader(env_file=env_file, keys=["BAZ", "FOO", "BAR", "EMPTY"])

    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    expected = {"FOO=bar", "BAR=quoted value", "BAZ=value with spaces", "EMPTY="}
    assert set(lines) == expected
    assert len(lines) == len(expected)


def test_env_loader_missing_file_returns_error(tmp_path: Path) -> None:
    env_file = tmp_path / "missing.env"

    result = run_env_loader(env_file=env_file, keys=["FOO"])

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == ""


def test_env_loader_requires_variables(tmp_path: Path) -> None:
    env_file = tmp_path / "only.env"
    env_file.write_text("FOO=bar\n", encoding="utf-8")

    result = run_env_loader(env_file=env_file)

    assert result.returncode == 2
    assert "Uso:" in result.stderr


def test_env_loader_supports_hash_values(tmp_path: Path) -> None:
    env_file = tmp_path / "hash.env"
    env_file.write_text(
        "\n".join(
            [
                "PASSWORD=#SuperSecret",
                "COMMENT=value    # inline comment",
                "COMMENT_TAB=value\t# another comment",
                "LITERAL=\\#escaped hash",
            ]
        ),
        encoding="utf-8",
    )

    result = run_env_loader(env_file=env_file, keys=["PASSWORD", "COMMENT", "COMMENT_TAB", "LITERAL"])

    assert result.returncode == 0
    assert set(result.stdout.splitlines()) == {
        "PASSWORD=#SuperSecret",
        "COMMENT=value",
        "COMMENT_TAB=value",
        "LITERAL=#escaped hash",
    }


def test_env_loader_preserves_hashes_in_quoted_values(tmp_path: Path) -> None:
    env_file = tmp_path / "quoted.env"
    env_file.write_text(
        "\n".join(
            [
                'QUOTED_HASH="#Keep #this"',
                'QUOTED_EMBEDDED="#value#with#hash"',
            ]
        ),
        encoding="utf-8",
    )

    result = run_env_loader(
        env_file=env_file,
        keys=["QUOTED_HASH", "QUOTED_EMBEDDED"],
    )

    assert result.returncode == 0, result.stderr
    assert set(result.stdout.splitlines()) == {
        "QUOTED_HASH=#Keep #this",
        "QUOTED_EMBEDDED=#value#with#hash",
    }
