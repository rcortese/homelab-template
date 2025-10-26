from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_env_sync.py"


def run_check(repo_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT_PATH), "--repo-root", str(repo_root)],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
    )


def test_check_env_sync_succeeds_when_everything_matches(repo_copy: Path) -> None:
    result = run_check(repo_copy)

    assert result.returncode == 0, result.stderr
    assert "Todas as variáveis de ambiente estão sincronizadas." in result.stdout


def test_check_env_sync_detects_missing_variables(repo_copy: Path) -> None:
    compose_file = repo_copy / "compose" / "apps" / "app" / "core.yml"
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      CORE_MISSING_VAR: ${CORE_MISSING_VAR}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "Instância 'core'" in result.stdout
    assert "CORE_MISSING_VAR" in result.stdout


def test_check_env_sync_detects_obsolete_variables(repo_copy: Path) -> None:
    env_file = repo_copy / "env" / "core.example.env"
    with env_file.open("a", encoding="utf-8") as handle:
        handle.write("UNUSED_ONLY_FOR_TEST=1\n")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "Variáveis obsoletas" in result.stdout
    assert "UNUSED_ONLY_FOR_TEST" in result.stdout


def test_check_env_sync_detects_missing_template(repo_copy: Path) -> None:
    env_file = repo_copy / "env" / "core.example.env"
    env_file.unlink()

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "Instância 'core' não possui arquivo env/<instancia>.example.env documentado." in result.stdout
    assert "Divergências encontradas entre manifests Compose e arquivos .env exemplo." in result.stdout
    assert "Todas as variáveis de ambiente estão sincronizadas." not in result.stdout


def test_check_env_sync_reports_metadata_failure(repo_copy: Path) -> None:
    base_file = repo_copy / "compose" / "base.yml"
    base_file.unlink()

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert result.stdout == ""
    assert "[!]" in result.stderr
    assert "compose/base.yml" in result.stderr
