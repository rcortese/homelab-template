from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Sequence

import pytest

from scripts._internal.python.check_env_sync import main
from scripts._internal.lib.check_env_sync.compose_metadata import (
    ComposeMetadata,
    decode_bash_string,
    load_compose_metadata,
    parse_declare_array,
    parse_declare_mapping,
)
from scripts._internal.lib.check_env_sync.compose_variables import extract_compose_variables
from scripts._internal.lib.check_env_sync.reporting import SyncReport, build_sync_report
from tests.helpers.compose_instances import ComposeInstancesData

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_env_sync.sh"


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

    raise AssertionError(
        f"Could not locate a Compose manifest for instance {instance_name!r}."
    )


def _resolve_env_template(
    repo_root: Path, compose_instances_data: ComposeInstancesData, instance_name: str
) -> Path:
    template_relative = compose_instances_data.env_template_map.get(instance_name)
    if template_relative:
        return repo_root / template_relative
    return repo_root / "env" / f"{instance_name}.example.env"


def run_check(repo_root: Path, extra_args: Sequence[str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    python_path = env.get("PYTHONPATH")
    entries = [str(repo_root)]
    if python_path:
        entries.append(python_path)
    env["PYTHONPATH"] = os.pathsep.join(entries)

    command = [str(SCRIPT_PATH), "--repo-root", str(repo_root)]
    if extra_args:
        command.extend(extra_args)

    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
        env=env,
    )


def test_check_env_sync_succeeds_when_everything_matches(repo_copy: Path) -> None:
    result = run_check(repo_copy)

    assert result.returncode == 0, result.stderr
    assert "All environment variables are in sync." in result.stdout


def test_load_metadata_accepts_instance_without_overrides(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    manifest = repo_copy / "compose" / f"docker-compose.{instance_name}.yml"
    if manifest.exists():
        manifest.unlink()

    metadata = load_compose_metadata(repo_copy)

    assert instance_name in metadata.instances
    assert metadata.files_by_instance[instance_name] == ()


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
    assert f"Instance '{instance_name}'" in result.stdout
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


def test_check_env_sync_ignores_variables_in_comments(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, instance_name)
    content = compose_file.read_text(encoding="utf-8")
    content += (
        "\n    environment:\n"
        "      # ${ONLY_IN_COMMENT}\n"
        "      COMMENTED_ENV: ${MISSING_FROM_ENV}"
    )
    compose_file.write_text(content + "\n", encoding="utf-8")

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "MISSING_FROM_ENV" in result.stdout
    assert "ONLY_IN_COMMENT" not in result.stdout


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
    assert "Obsolete variables" in result.stdout
    assert "UNUSED_ONLY_FOR_TEST" in result.stdout


def test_check_env_sync_instance_option_limits_validation(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    if len(compose_instances_data.instance_names) < 2:
        pytest.skip("At least two instances are required to validate instance filtering.")

    target_instance = compose_instances_data.instance_names[0]
    other_instance = compose_instances_data.instance_names[1]
    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, other_instance)
    missing_variable = "ONLY_FOR_OTHER_INSTANCE"
    content = compose_file.read_text(encoding="utf-8")
    content += f"\n      FILTER_TEST_VAR: ${{{missing_variable}}}"
    compose_file.write_text(content, encoding="utf-8")

    result_target = run_check(repo_copy, ["--instance", target_instance])

    assert result_target.returncode == 0, result_target.stdout

    result_other = run_check(repo_copy, ["--instance", other_instance])

    assert result_other.returncode == 1
    assert missing_variable in result_other.stdout


def test_check_env_sync_deduplicates_instance_arguments(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    if len(compose_instances_data.instance_names) < 2:
        pytest.skip("At least two instances are required to validate instance filtering.")

    target_instance = compose_instances_data.instance_names[0]
    error_instance = compose_instances_data.instance_names[1]

    compose_file = _resolve_compose_manifest(repo_copy, compose_instances_data, error_instance)
    missing_variable = "ONLY_FOR_DEDUP_TEST"
    content = compose_file.read_text(encoding="utf-8")
    content += f"\n      DEDUP_TEST_VAR: ${{{missing_variable}}}"
    compose_file.write_text(content, encoding="utf-8")

    result = run_check(
        repo_copy,
        [
            "--instance",
            f"{target_instance}, {error_instance}",
            "--instance",
            target_instance,
        ],
    )

    assert result.returncode == 1
    assert missing_variable in result.stdout
    assert result.stdout.count(f"Instance '{error_instance}'") == 1
    assert f"Instance '{target_instance}'" not in result.stdout


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
    assert "LOCAL_INSTANCE" not in missing_vars

    monkeypatch.setattr(
        "scripts._internal.lib.check_env_sync.reporting.RUNTIME_PROVIDED_VARIABLES", set()
    )

    report_without_runtime = build_sync_report(repo_copy, metadata)
    missing_without_runtime = {
        variable
        for variables in report_without_runtime.missing_by_instance.values()
        for variable in variables
    }
    assert "LOCAL_INSTANCE" in missing_without_runtime


def test_build_sync_report_uses_common_and_implicit_vars(monkeypatch, tmp_path: Path) -> None:
    repo_root = tmp_path
    base_file = repo_root / "compose" / "docker-compose.common.yml"
    base_file.parent.mkdir(parents=True, exist_ok=True)
    base_file.write_text(
        """
services:
  app:
    environment:
      COMMON_FROM_TEMPLATE: ${COMMON_FROM_TEMPLATE}
      LOCAL_COMMON_ONLY: ${LOCAL_COMMON_ONLY}
      IMPLICIT_VAR: ${IMPLICIT_FROM_MONKEYPATCH}
""".strip(),
        encoding="utf-8",
    )

    overrides_dir = repo_root / "compose" / "overrides"
    overrides_dir.mkdir(parents=True, exist_ok=True)
    core_override = overrides_dir / "core.yml"
    core_override.write_text(
        """
services:
  app:
    environment:
      CORE_SPECIFIC: ${CORE_SPECIFIC_VAR}
""".strip(),
        encoding="utf-8",
    )

    env_dir = repo_root / "env"
    env_dir.mkdir(parents=True, exist_ok=True)
    common_env = env_dir / "common.example.env"
    common_env.write_text("COMMON_FROM_TEMPLATE=\n", encoding="utf-8")
    local_common_env = env_dir / "local" / "common.env"
    local_common_env.parent.mkdir(parents=True, exist_ok=True)
    local_common_env.write_text("LOCAL_COMMON_ONLY=\n", encoding="utf-8")

    core_env = env_dir / "core.example.env"
    core_env.write_text("CORE_SPECIFIC_VAR=\nUNUSED_ONLY=\n", encoding="utf-8")

    metadata = ComposeMetadata(
        base_file=base_file.resolve(),
        instances=["core"],
        files_by_instance={"core": [core_override.resolve()]},
        env_template_by_instance={"core": core_env.resolve()},
    )

    monkeypatch.setattr(
        "scripts._internal.lib.check_env_sync.reporting.IMPLICIT_ENV_VARS",
        {"IMPLICIT_FROM_MONKEYPATCH"},
    )

    report = build_sync_report(repo_root, metadata)

    assert report.missing_by_instance == {"core": set()}
    assert report.missing_templates == []
    assert report.unused_by_file == {core_env.resolve(): {"UNUSED_ONLY"}}


def test_check_env_sync_reports_unknown_instance(repo_copy: Path) -> None:
    result = run_check(repo_copy, ["--instance", "unknown-instance"])

    assert result.returncode == 1
    assert "Unknown instances" in result.stderr


def test_check_env_sync_detects_missing_template(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    instance_name = _select_instance(compose_instances_data)
    env_file = _resolve_env_template(repo_copy, compose_instances_data, instance_name)
    env_file.unlink()

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert (
        f"Instance '{instance_name}' does not have a documented env/<instance>.example.env file."
        in result.stdout
    )
    assert "Differences found between Compose manifests and example .env files." in result.stdout
    assert "All environment variables are in sync." not in result.stdout


def test_check_env_sync_allows_missing_base_file(repo_copy: Path) -> None:
    base_paths = [
        repo_copy / "compose" / "docker-compose.common.yml",
    ]
    for base_file in base_paths:
        if base_file.exists():
            base_file.unlink()

    result = run_check(repo_copy)

    assert result.returncode == 0
    assert "compose/docker-compose.common.yml" not in result.stderr
    assert "All environment variables are in sync." in result.stdout
    assert "Obsolete variables in env/core.example.env:" not in result.stdout


def test_check_env_sync_reports_missing_compose_override(repo_copy: Path) -> None:
    script_path = repo_copy / "scripts" / "_internal" / "lib" / "compose_instances.sh"
    script_path.write_text(
        """#!/usr/bin/env bash
cat <<'EOF'
declare -- BASE_COMPOSE_FILE="compose/docker-compose.common.yml"
declare -a COMPOSE_INSTANCE_NAMES=([0]="core")
declare -A COMPOSE_INSTANCE_FILES=([core]=$'compose/missing.yml')
declare -A COMPOSE_INSTANCE_ENV_LOCAL=([core]=$'env/local/core.env')
declare -A COMPOSE_INSTANCE_ENV_TEMPLATES=([core]=$'env/core.example.env')
declare -A COMPOSE_INSTANCE_ENV_FILES=([core]=$'env/local/core.env')
EOF
""",
        encoding="utf-8",
    )
    script_path.chmod(0o755)

    result = run_check(repo_copy)

    missing_path = (repo_copy / "compose" / "missing.yml").resolve()
    assert result.returncode == 1
    assert "[!]" in result.stderr
    assert "Compose file missing" in result.stderr
    assert str(missing_path) in result.stderr


def test_check_env_sync_reports_metadata_error_from_compose_script(repo_copy: Path) -> None:
    script_path = repo_copy / "scripts" / "_internal" / "lib" / "compose_instances.sh"
    stub_error = "Simulated error while loading instances."
    script_path.write_text(
        f"""#!/usr/bin/env bash
echo "{stub_error}" >&2
exit 1
""",
        encoding="utf-8",
    )
    script_path.chmod(0o755)

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert stub_error in result.stderr
    assert "[!]" in result.stderr


def test_check_env_sync_errors_when_declared_base_missing(repo_copy: Path) -> None:
    script_path = repo_copy / "scripts" / "_internal" / "lib" / "compose_instances.sh"
    script_path.write_text(
        """#!/usr/bin/env bash
cat <<'EOF'
declare -- BASE_COMPOSE_FILE="compose/missing-base.yml"
declare -a COMPOSE_INSTANCE_NAMES=([0]="core")
declare -A COMPOSE_INSTANCE_FILES=([core]=$'compose/docker-compose.core.yml')
declare -A COMPOSE_INSTANCE_ENV_LOCAL=([core]=$'env/local/core.env')
declare -A COMPOSE_INSTANCE_ENV_TEMPLATES=([core]=$'env/core.example.env')
declare -A COMPOSE_INSTANCE_ENV_FILES=([core]=$'env/local/core.env')
EOF
""",
        encoding="utf-8",
    )
    script_path.chmod(0o755)

    result = run_check(repo_copy)

    assert result.returncode == 1
    assert "Declared base file is missing" in result.stderr


def test_main_filters_instances_before_build(monkeypatch, tmp_path: Path) -> None:
    base_file = tmp_path / "compose" / "docker-compose.common.yml"
    base_file.parent.mkdir(parents=True, exist_ok=True)
    base_file.write_text("version: '3.9'\n", encoding="utf-8")

    metadata = ComposeMetadata(
        base_file=base_file,
        instances=["alpha", "beta"],
        files_by_instance={
            "alpha": [tmp_path / "compose" / "alpha.yml"],
            "beta": [tmp_path / "compose" / "beta.yml"],
        },
        env_template_by_instance={
            "alpha": tmp_path / "env" / "alpha.example.env",
            "beta": tmp_path / "env" / "beta.example.env",
        },
    )

    captured_metadata: list[ComposeMetadata] = []

    def fake_load(repo_root: Path) -> ComposeMetadata:
        return metadata

    def fake_build(repo_root: Path, current_metadata: ComposeMetadata) -> SyncReport:
        captured_metadata.append(current_metadata)
        return SyncReport(
            missing_by_instance={"beta": set()},
            unused_by_file={},
            missing_templates=[],
        )

    monkeypatch.setattr("scripts._internal.python.check_env_sync.load_compose_metadata", fake_load)
    monkeypatch.setattr("scripts._internal.python.check_env_sync.build_sync_report", fake_build)

    exit_code = main(["--repo-root", str(tmp_path), "--instance", "beta"])

    assert exit_code == 0
    assert captured_metadata, "build_sync_report was not called"
    filtered_metadata = captured_metadata[0]
    assert filtered_metadata.instances == ["beta"]
    assert set(filtered_metadata.files_by_instance.keys()) == {"beta"}
    assert set(filtered_metadata.env_template_by_instance.keys()) == {"beta"}


def test_build_sync_report_handles_shared_base(tmp_path: Path) -> None:
    repo_root = tmp_path
    base_file = repo_root / "compose" / "docker-compose.common.yml"
    base_file.parent.mkdir(parents=True, exist_ok=True)
    base_file.write_text(
        """
services:
  shared:
    environment:
      SHARED_VAR: ${SHARED_VAR}
""".strip(),
        encoding="utf-8",
    )

    overrides_dir = repo_root / "compose" / "overrides"
    overrides_dir.mkdir(parents=True, exist_ok=True)
    core_override = overrides_dir / "core.yml"
    core_override.write_text(
        """
services:
  core:
    environment:
      CORE_ONLY_VAR: ${CORE_ONLY_VAR}
""".strip(),
        encoding="utf-8",
    )
    media_override = overrides_dir / "media.yml"
    media_override.write_text(
        """
services:
  media:
    environment:
      MEDIA_ONLY_VAR: ${MEDIA_ONLY_VAR}
""".strip(),
        encoding="utf-8",
    )

    env_dir = repo_root / "env"
    env_dir.mkdir(parents=True, exist_ok=True)
    core_env = env_dir / "core.example.env"
    core_env.write_text("SHARED_VAR=\nCORE_ONLY_VAR=\n", encoding="utf-8")
    media_env = env_dir / "media.example.env"
    media_env.write_text("SHARED_VAR=\nMEDIA_ONLY_VAR=\n", encoding="utf-8")

    metadata = ComposeMetadata(
        base_file=base_file.resolve(),
        instances=["core", "media"],
        files_by_instance={
            "core": [core_override.resolve()],
            "media": [media_override.resolve()],
        },
        env_template_by_instance={
            "core": core_env.resolve(),
            "media": media_env.resolve(),
        },
    )

    report = build_sync_report(repo_root, metadata)

    assert report.missing_by_instance == {"core": set(), "media": set()}
    assert report.unused_by_file == {}
    assert report.missing_templates == []


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


def test_extract_compose_variables_fallback_on_yaml_error(tmp_path: Path) -> None:
    compose_file = tmp_path / "broken.yml"
    compose_file.write_text(
        """
services:
  app:
    environment:
      BROKEN: "${MALFORMED_VAR}
""".lstrip(),
        encoding="utf-8",
    )

    with pytest.raises(ComposeMetadataError, match="Failed to parse YAML"):
        extract_compose_variables([compose_file])
