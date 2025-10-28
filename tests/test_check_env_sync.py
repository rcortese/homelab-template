from __future__ import annotations

import os
import subprocess
from pathlib import Path

from scripts.check_env_sync import (
    build_sync_report,
    decode_bash_string,
    load_compose_metadata,
    parse_declare_array,
    parse_declare_mapping,
)
from tests.helpers.compose_instances import ComposeInstancesData

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_env_sync.py"


def _select_instance(compose_instances_data: ComposeInstancesData) -> str:
    if "core" in compose_instances_data.instance_names:
        return "core"
    return compose_instances_data.instance_names[0]


def _resolve_compose_manifest(
    repo_root: Path, compose_instances_data: ComposeInstancesData, instance_name: str
) -> Path:
    for relative in compose_instances_data.instance_files.get(instance_name, []):
        candidate = repo_root / relative
        if candidate.is_file():
            return candidate

    compose_apps = repo_root / "compose" / "apps"
    for candidate in sorted(compose_apps.glob(f"*/{instance_name}.yml")):
        if candidate.is_file():
            return candidate

    raise AssertionError(
        f"Não foi possível localizar um manifest Compose para a instância {instance_name!r}."
    )


def _resolve_env_template(
    repo_root: Path, compose_instances_data: ComposeInstancesData, instance_name: str
) -> Path:
    template_relative = compose_instances_data.env_template_map.get(instance_name)
    if template_relative:
        return repo_root / template_relative
    return repo_root / "env" / f"{instance_name}.example.env"


def run_check(repo_root: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    python_path = env.get("PYTHONPATH")
    entries = [str(repo_root)]
    if python_path:
        entries.append(python_path)
    env["PYTHONPATH"] = os.pathsep.join(entries)

    return subprocess.run(
        [str(SCRIPT_PATH), "--repo-root", str(repo_root)],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
        env=env,
    )


def test_check_env_sync_succeeds_when_everything_matches(repo_copy: Path) -> None:
    result = run_check(repo_copy)

    assert result.returncode == 0, result.stderr
    assert "Todas as variáveis de ambiente estão sincronizadas." in result.stdout


def test_check_env_sync_detects_missing_variables(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, instance_name)
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      CORE_MISSING_VAR: ${CORE_MISSING_VAR}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert f"Instância '{instance_name}'" in result.stdout
    assert "CORE_MISSING_VAR" in result.stdout


def test_check_env_sync_detects_plain_and_nested_variables(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, instance_name)
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      PLAIN_REFERENCE: $PLAIN_MISSING_VAR"
    content += "\n      COMPLEX_PATH: ${OUTER_VAR:-./${INNER_VAR:-fallback}}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "PLAIN_MISSING_VAR" in result.stdout
    assert "OUTER_VAR" in result.stdout
    assert "INNER_VAR" in result.stdout


def test_check_env_sync_ignores_escaped_dollar_variables(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, instance_name)
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      ESCAPED_LITERAL: \"$$SHOULD_NOT_APPEAR\""
    content += "\n      ESCAPED_TEMPLATE_LITERAL: \"$$${SHOULD_NOT_APPEAR_NESTED}\""
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 0, result.stdout
    assert "SHOULD_NOT_APPEAR" not in result.stdout
    assert "SHOULD_NOT_APPEAR_NESTED" not in result.stdout


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


def test_check_env_sync_accepts_local_implicit_variables(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, instance_name)
    content = compose_file.read_text(encoding="utf-8")
    content += "\n      LOCAL_IMPLICIT_FROM_OVERRIDE: ${FOO_FROM_LOCAL}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 0, result.stdout
    assert "FOO_FROM_LOCAL" not in result.stdout


def test_check_env_sync_detects_obsolete_variables(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    env_file = _resolve_env_template(
        repo_copy, compose_instances_data, _select_instance(compose_instances_data)
    )
    with env_file.open("a", encoding="utf-8") as handle:
        handle.write("UNUSED_ONLY_FOR_TEST=1\n")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "Variáveis obsoletas" in result.stdout
    assert "UNUSED_ONLY_FOR_TEST" in result.stdout


def test_build_sync_report_uses_runtime_provided_variables(
    repo_copy: Path, monkeypatch
) -> None:
    metadata = load_compose_metadata(repo_copy)

    report = build_sync_report(repo_copy, metadata)
    missing_vars = {
        variable
        for variables in report.missing_by_instance.values()
        for variable in variables
    }
    assert "PWD" not in missing_vars

    monkeypatch.setattr("scripts.check_env_sync.RUNTIME_PROVIDED_VARIABLES", set())

    report_without_runtime = build_sync_report(repo_copy, metadata)
    missing_without_runtime = {
        variable
        for variables in report_without_runtime.missing_by_instance.values()
        for variable in variables
    }
    assert "PWD" in missing_without_runtime


def test_check_env_sync_detects_missing_template(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    env_file = _resolve_env_template(repo_copy, compose_instances_data, instance_name)
    env_file.unlink()

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert (
        f"Instância '{instance_name}' não possui arquivo env/<instancia>.example.env documentado."
        in result.stdout
    )
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


def test_check_env_sync_reports_missing_compose_override(repo_copy: Path) -> None:
    script_path = repo_copy / "scripts" / "lib" / "compose_instances.sh"
    script_path.write_text(
        """#!/usr/bin/env bash
cat <<'EOF'
declare -- BASE_COMPOSE_FILE="compose/base.yml"
declare -a COMPOSE_INSTANCE_NAMES=([0]="core")
declare -A COMPOSE_INSTANCE_FILES=([core]=$'compose/missing.yml')
declare -A COMPOSE_INSTANCE_ENV_LOCAL=([core]=$'env/local/core.env')
declare -A COMPOSE_INSTANCE_ENV_TEMPLATES=([core]=$'env/core.example.env')
declare -A COMPOSE_INSTANCE_ENV_FILES=([core]=$'env/local/core.env')
declare -A COMPOSE_INSTANCE_APP_NAMES=([core]=$'')
declare -A COMPOSE_APP_BASE_FILES=([core]=$'')
EOF
""",
        encoding="utf-8",
    )
    script_path.chmod(0o755)

    result = run_check(repo_copy)

    missing_path = (repo_copy / "compose" / "missing.yml").resolve()
    assert result.returncode == 1
    assert "[!]" in result.stderr
    assert "Arquivo Compose ausente" in result.stderr
    assert str(missing_path) in result.stderr


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
