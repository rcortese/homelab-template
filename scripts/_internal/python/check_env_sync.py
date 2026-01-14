#!/usr/bin/env python3
"""Check that Docker Compose manifests and env templates stay in sync."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Sequence, Set

from scripts._internal.lib.check_env_sync.compose_metadata import (
    ComposeMetadata,
    ComposeMetadataError,
    load_compose_metadata,
)
from scripts._internal.lib.check_env_sync.reporting import (
    build_sync_report,
    determine_exit_code,
    format_report,
)


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
    repo_root = (
        Path(args.repo_root).resolve()
        if args.repo_root
        else Path(__file__).resolve().parents[3]
    )

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
