#!/usr/bin/env python3
"""Validate compose YAML structure for required keys."""

from __future__ import annotations

import sys
from collections.abc import Mapping
from pathlib import Path

import yaml


def _type_label(value: object) -> str:
    if value is None:
        return "null"
    return type(value).__name__


def _check_services_mapping(path: Path) -> int:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return 1

    try:
        documents = list(yaml.safe_load_all(content))
    except yaml.YAMLError as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return 1

    if not documents:
        documents = [None]

    for document in documents:
        services = None
        if isinstance(document, Mapping):
            services = document.get("services")

        if services is None:
            print(
                f"{path}: Invalid compose: services must be a mapping (is null).",
                file=sys.stderr,
            )
            return 1

        if not isinstance(services, Mapping):
            print(
                f"{path}: Invalid compose: services must be a mapping (is {_type_label(services)}).",
                file=sys.stderr,
            )
            return 1

    return 0


def main() -> int:
    if len(sys.argv) <= 1:
        print("Usage: validate_compose_yaml.py <compose.yml> [...]", file=sys.stderr)
        return 2

    status = 0
    for raw_path in sys.argv[1:]:
        path = Path(raw_path)
        if _check_services_mapping(path) != 0:
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
