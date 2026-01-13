#!/usr/bin/env python3
"""Check that Docker Compose manifests and env templates stay in sync."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Sequence, Set

from scripts.lib.check_env_sync.compose_metadata import (
    ComposeMetadata,
    ComposeMetadataError,
    decode_bash_string,
    load_compose_metadata,
    parse_declare_array,
    parse_declare_mapping,
)
from scripts.lib.check_env_sync.compose_variables import extract_compose_variables
from scripts.lib.check_env_sync.env_templates import EnvTemplateData, load_env_variables
from scripts.lib.check_env_sync.reporting import (
    SyncReport,
    build_sync_report as _build_sync_report,
    determine_exit_code,
    format_report,
)

RUNTIME_PROVIDED_VARIABLES: Set[str] = {"LOCAL_INSTANCE", "REPO_ROOT"}
DEFAULT_IMPLICIT_ENV_VARS: Set[str] = {"APP_DATA_UID", "APP_DATA_GID"}
try:  # pragma: no cover - optional local overrides
    from scripts.local.check_env_sync import IMPLICIT_ENV_VARS  # type: ignore[attr-defined]
except ModuleNotFoundError:  # pragma: no cover - default fallback
    IMPLICIT_ENV_VARS: Set[str] = set()


def build_sync_report(repo_root: Path, metadata: ComposeMetadata) -> SyncReport:
    implicit_vars = set(DEFAULT_IMPLICIT_ENV_VARS)
    implicit_vars.update(IMPLICIT_ENV_VARS)
    return _build_sync_report(
        repo_root,
        metadata,
        runtime_provided_vars=RUNTIME_PROVIDED_VARIABLES,
        implicit_env_vars=implicit_vars,
    )

__all__ = [
    "ComposeMetadata",
    "ComposeMetadataError",
    "DEFAULT_IMPLICIT_ENV_VARS",
    "EnvTemplateData",
    "IMPLICIT_ENV_VARS",
    "RUNTIME_PROVIDED_VARIABLES",
    "SyncReport",
    "build_sync_report",
    "decode_bash_string",
    "determine_exit_code",
    "extract_compose_variables",
    "format_report",
    "load_compose_metadata",
    "load_env_variables",
    "parse_declare_array",
    "parse_declare_mapping",
]


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate .env variables against Compose manifests."
    )
    parser.add_argument(
        "--repo-root",
        dest="repo_root",
        default=None,
        help="Repository root directory (default: parent of scripts/).",
    )
    parser.add_argument(
        "--instance",
        dest="instances",
        action="append",
        default=None,
        help=(
            "Restrict validation to the provided instances. Can be repeated or supplied as a comma-separated list."
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[1]

    try:
        metadata = load_compose_metadata(repo_root)
        if args.instances:
            requested_instances: List[str] = []
            seen: Set[str] = set()
            for raw_value in args.instances:
                parts = [part.strip() for part in raw_value.split(",") if part.strip()]
                if not parts:
                    continue
                for candidate in parts:
                    if candidate not in seen:
                        requested_instances.append(candidate)
                        seen.add(candidate)

            if not requested_instances:
                print("[!] No valid instance was provided.", file=sys.stderr)
                return 1

            known_instances = set(metadata.instances)
            missing_instances = sorted(set(requested_instances) - known_instances)
            if missing_instances:
                formatted = ", ".join(missing_instances)
                print(f"[!] Unknown instances: {formatted}.", file=sys.stderr)
                return 1

            filtered_instances = [
                instance for instance in metadata.instances if instance in seen
            ]
            files_by_instance = {
                instance: metadata.files_by_instance[instance]
                for instance in filtered_instances
            }
            env_template_by_instance = {
                instance: metadata.env_template_by_instance.get(instance)
                for instance in filtered_instances
            }

            metadata = ComposeMetadata(
                base_file=metadata.base_file,
                instances=filtered_instances,
                files_by_instance=files_by_instance,
                env_template_by_instance=env_template_by_instance,
            )

        report = build_sync_report(repo_root, metadata)
    except ComposeMetadataError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(f"[!] Expected file not found: {exc}", file=sys.stderr)
        return 1

    output = format_report(repo_root, report)
    print(output)
    return determine_exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
