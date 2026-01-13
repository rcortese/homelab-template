"""Reporting helpers for env sync checks."""

from __future__ import annotations

import importlib
import importlib.util
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Mapping, Sequence, Set

from scripts.lib.check_env_sync.compose_metadata import ComposeMetadata
from scripts.lib.check_env_sync.compose_variables import extract_compose_variables
from scripts.lib.check_env_sync.env_templates import EnvTemplateData, load_env_variables

RUNTIME_PROVIDED_VARIABLES: Set[str] = {"LOCAL_INSTANCE", "REPO_ROOT"}
DEFAULT_IMPLICIT_ENV_VARS: Set[str] = {"APP_DATA_UID", "APP_DATA_GID"}


def _load_implicit_env_vars() -> Set[str]:
    spec = importlib.util.find_spec("scripts.local.check_env_sync")
    if spec is None:
        return set()
    module = importlib.import_module("scripts.local.check_env_sync")
    return set(getattr(module, "IMPLICIT_ENV_VARS", set()))


@dataclass
class SyncReport:
    missing_by_instance: Mapping[str, Set[str]]
    unused_by_file: Mapping[Path, Set[str]]
    missing_templates: Sequence[str]

    @property
    def has_issues(self) -> bool:
        return (
            any(values for values in self.missing_by_instance.values())
            or any(values for values in self.unused_by_file.values())
            or bool(self.missing_templates)
        )


def build_sync_report(repo_root: Path, metadata: ComposeMetadata) -> SyncReport:
    variable_cache: Dict[Path, Set[str]] = {}

    def cached_compose_variables(path: Path) -> Set[str]:
        normalized = path.resolve()
        cached = variable_cache.get(normalized)
        if cached is None:
            cached = extract_compose_variables([normalized])
            variable_cache[normalized] = cached
        return cached

    def gather_variables(paths: Sequence[Path]) -> Set[str]:
        collected: Set[str] = set()
        for entry in paths:
            collected.update(cached_compose_variables(entry))
        return collected

    base_sources: list[Path] = []
    if metadata.base_file is not None:
        base_sources.append(metadata.base_file)

    base_vars = gather_variables(base_sources)
    compose_vars_by_instance: Dict[str, Set[str]] = {}
    for instance, files in metadata.files_by_instance.items():
        instance_vars = set(base_vars)
        instance_vars.update(gather_variables(files))
        compose_vars_by_instance[instance] = instance_vars

    common_env_path = repo_root / "env" / "common.example.env"
    local_common_path = repo_root / "env" / "local" / "common.env"
    instance_env_files: Dict[Path, EnvTemplateData] = {}

    empty_env_data = EnvTemplateData(defined=set(), documented=set())
    common_env_data = load_env_variables(common_env_path) if common_env_path.exists() else empty_env_data
    local_common_data = (
        load_env_variables(local_common_path) if local_common_path.exists() else empty_env_data
    )
    common_env_vars = set(common_env_data.available)
    common_env_vars.update(local_common_data.available)
    implicit_env_vars = set(DEFAULT_IMPLICIT_ENV_VARS)
    implicit_env_vars.update(_load_implicit_env_vars())
    common_env_vars.update(implicit_env_vars)

    missing_templates: List[str] = []
    for instance in metadata.instances:
        template_path = metadata.env_template_by_instance.get(instance)
        if template_path is None or not template_path.exists():
            missing_templates.append(instance)
            continue
        instance_env_files[template_path] = load_env_variables(template_path)

    missing_by_instance: Dict[str, Set[str]] = {}
    for instance, compose_vars in compose_vars_by_instance.items():
        template_path = metadata.env_template_by_instance.get(instance)
        data = instance_env_files.get(template_path) if template_path else None
        instance_env_vars = data.available if data else set()
        available = set(common_env_vars)
        available.update(RUNTIME_PROVIDED_VARIABLES)
        available.update(instance_env_vars)
        missing_by_instance[instance] = compose_vars - available

    unused_by_file: Dict[Path, Set[str]] = {}
    for path, data in instance_env_files.items():
        instance = next(
            (name for name, template in metadata.env_template_by_instance.items() if template == path),
            None,
        )
        relevant_compose = compose_vars_by_instance.get(instance, set())
        unused = data.defined - relevant_compose - implicit_env_vars - RUNTIME_PROVIDED_VARIABLES
        if unused:
            unused_by_file[path] = unused

    return SyncReport(
        missing_by_instance=missing_by_instance,
        unused_by_file=unused_by_file,
        missing_templates=missing_templates,
    )


def format_report(repo_root: Path, report: SyncReport) -> str:
    lines: List[str] = []
    lines.append("Checking environment variables referenced by Compose manifests...")
    lines.append("")

    for instance, missing in sorted(report.missing_by_instance.items()):
        if not missing:
            continue
        lines.append(f"Instance '{instance}':")
        for var in sorted(missing):
            lines.append(f"  - Missing variable: {var}")
        lines.append("")

    for template in sorted(report.missing_templates):
        lines.append(
            f"Instance '{template}' does not have a documented env/<instance>.example.env file."
        )
    if report.missing_templates:
        lines.append("")

    for path, unused in sorted(report.unused_by_file.items(), key=lambda item: str(item[0])):
        rel_path = path.relative_to(repo_root)
        lines.append(f"Obsolete variables in {rel_path}:")
        for var in sorted(unused):
            lines.append(f"  - {var}")
        lines.append("")

    if not report.has_issues:
        lines.append("All environment variables are in sync.")
    else:
        lines.append("Differences found between Compose manifests and example .env files.")

    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def determine_exit_code(report: SyncReport) -> int:
    return 1 if report.has_issues else 0
