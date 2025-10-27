from __future__ import annotations

import subprocess
from pathlib import Path

from scripts.check_env_sync import decode_bash_string, parse_declare_array, parse_declare_mapping

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


def test_check_env_sync_detects_plain_and_nested_variables(repo_copy: Path) -> None:
    compose_file = repo_copy / "compose" / "apps" / "app" / "core.yml"
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      PLAIN_REFERENCE: $PLAIN_MISSING_VAR"
    content += "\n      COMPLEX_PATH: ${OUTER_VAR:-./${INNER_VAR:-fallback}}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "PLAIN_MISSING_VAR" in result.stdout
    assert "OUTER_VAR" in result.stdout
    assert "INNER_VAR" in result.stdout


def test_check_env_sync_accepts_local_common_variables(repo_copy: Path) -> None:
    common_example_path = repo_copy / "env" / "common.example.env"
    content = common_example_path.read_text(encoding="utf-8")
    content = content.replace("APP_SECRET=defina-uma-chave-segura\n", "")
    common_example_path.write_text(content, encoding="utf-8")

    local_common_path = repo_copy / "env" / "local" / "common.env"
    local_common_path.parent.mkdir(parents=True, exist_ok=True)
    local_common_path.write_text("APP_SECRET=local-value\n", encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 0, result.stdout
    assert "APP_SECRET" not in result.stdout


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


def test_decode_bash_string_handles_dollar_single_quotes() -> None:
    token = "$'multi\\nline\\tvalue'"

    result = decode_bash_string(token)

    assert result == "multi\nline\tvalue"


def test_parse_declare_array_with_mixed_quotes_preserves_order() -> None:
    line = "declare -a COMPOSE_INSTANCE_NAMES=([0]=\"core\" [2]=$'media\\n' [1]='edge')"

    result = parse_declare_array(line)

    assert result == ["core", "edge", "media\n"]


def test_parse_declare_mapping_with_multiple_entries_and_escapes() -> None:
    line = "declare -A MAP=([foo]=$'line\\nA' [bar]=\"line\\nB\" [baz]=$'tab\\tvalue')"

    result = parse_declare_mapping(line)

    assert list(result.keys()) == ["foo", "bar", "baz"]
    assert result["foo"] == "line\nA"
    assert result["bar"] == "line\nB"
    assert result["baz"] == "tab\tvalue"
