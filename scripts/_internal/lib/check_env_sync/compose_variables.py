"""Extract environment substitution variables from Compose YAML files."""

from __future__ import annotations

import sys
from collections.abc import Mapping as MappingCollection
from collections.abc import Sequence as SequenceCollection
from collections.abc import Set as SetCollection
from pathlib import Path
from typing import Iterable, List, Set

import yaml

from scripts._internal.lib.check_env_sync.compose_metadata import ComposeMetadataError


def _collect_substitution_variables(text: str) -> Set[str]:
    """Collect variable names from Docker Compose substitution expressions."""

    variables: Set[str] = set()
    length = len(text)
    index = 0

    while index < length:
        char = text[index]
        if char == "$":
            if index > 0 and text[index - 1] == "$":
                index += 1
                continue
            if text.startswith("$$${", index):
                index += 1
                continue
            next_index = index + 1
            if next_index < length and text[next_index] == "{":
                brace_depth = 1
                inner_start = next_index + 1
                cursor = inner_start
                while cursor < length and brace_depth:
                    current = text[cursor]
                    if current == "{":
                        brace_depth += 1
                    elif current == "}":
                        brace_depth -= 1
                    cursor += 1
                if brace_depth == 0:
                    inner_expression = text[inner_start : cursor - 1]
                    variables.update(_parse_parameter_expression(inner_expression))
                    index = cursor
                    continue
            else:
                if next_index < length and (
                    text[next_index].isalpha() or text[next_index] == "_"
                ):
                    cursor = next_index + 1
                    while cursor < length and (
                        text[cursor].isalnum() or text[cursor] == "_"
                    ):
                        cursor += 1
                    variables.add(text[next_index:cursor])
                    index = cursor
                    continue
        index += 1

    return variables


def _strip_inline_comment(text: str) -> str:
    """Remove inline comments while keeping quoted "#" characters."""

    result: List[str] = []
    in_single = False
    in_double = False
    escape = False

    for char in text:
        if escape:
            result.append(char)
            escape = False
            continue
        if char == "\\":
            result.append(char)
            escape = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            result.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            result.append(char)
            continue
        if char == "#" and not in_single and not in_double:
            break
        result.append(char)

    return "".join(result)


def _collect_variables_from_text(text: str) -> Set[str]:
    """Fallback variable extraction that ignores comment-only lines."""

    variables: Set[str] = set()
    for raw_line in text.splitlines():
        stripped = raw_line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        cleaned = _strip_inline_comment(stripped)
        if cleaned:
            variables.update(_collect_substitution_variables(cleaned))
    return variables


def _parse_parameter_expression(expression: str) -> Set[str]:
    expression = expression.strip()
    if not expression:
        return set()

    variables: Set[str] = set()

    index = 0
    length = len(expression)

    while index < length and expression[index] == "!":
        index += 1

    start = index
    if index < length and (expression[index].isalpha() or expression[index] == "_"):
        index += 1
        while index < length and (
            expression[index].isalnum() or expression[index] == "_"
        ):
            index += 1
        variable_name = expression[start:index]
        if variable_name:
            variables.add(variable_name)

    remainder = expression[index:]
    if remainder:
        variables.update(_collect_substitution_variables(remainder))

    return variables


def _iter_yaml_strings(node: object) -> Iterable[str]:
    if isinstance(node, str):
        yield node
        return
    if isinstance(node, MappingCollection):
        for value in node.values():
            yield from _iter_yaml_strings(value)
        return
    if isinstance(node, SequenceCollection) and not isinstance(
        node, (str, bytes, bytearray)
    ):
        for item in node:
            yield from _iter_yaml_strings(item)
        return
    if isinstance(node, SetCollection):
        for item in node:
            yield from _iter_yaml_strings(item)


def extract_compose_variables(paths: Iterable[Path]) -> Set[str]:
    variables: Set[str] = set()
    for path in paths:
        try:
            content = path.read_text(encoding="utf-8")
        except FileNotFoundError as exc:
            raise ComposeMetadataError(f"Compose file missing: {path}") from exc
        try:
            for document in yaml.safe_load_all(content):
                for value in _iter_yaml_strings(document):
                    variables.update(_collect_substitution_variables(value))
        except yaml.YAMLError as exc:  # pragma: no cover - defensive parsing fallback
            print(
                f"[!] Failed to parse YAML in {path}: {exc}. Using heuristic fallback.",
                file=sys.stderr,
            )
            variables.update(_collect_variables_from_text(content))
    return variables
