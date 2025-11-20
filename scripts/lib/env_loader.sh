#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/python_runtime.sh
source "${SCRIPT_DIR}/python_runtime.sh"

print_usage() {
  cat <<'EOF'
Uso: scripts/lib/env_loader.sh <arquivo.env> <VARIAVEL> [VARIAVEL...]

Lê um arquivo .env simples e imprime pares chave=valor para as variáveis
solicitadas. O script não altera o ambiente atual; cabe ao chamador decidir
como aplicar os pares retornados.
EOF
}

if [[ $# -lt 2 ]]; then
  print_usage >&2
  exit 2
fi

ENV_FILE="$1"
shift

if [[ ! -f "$ENV_FILE" ]]; then
  exit 1
fi

python_runtime__run_stdin "$REPO_ROOT" "" -- "$ENV_FILE" "$@" <<'PY'
import re
import sys
from pathlib import Path

def find_comment_index(value: str) -> int | None:
    r"""Locate the start of an inline comment, if any.

    A comment begins at an unescaped ``#`` character that is either the first
    character in the value or is immediately preceded by whitespace. Escaped
    hash characters (``\#``) should be preserved as literals.
    """

    for index, char in enumerate(value):
        if char != "#":
            continue

        if index == 0:
            # Leading '#'-only values are handled separately in normalize().
            continue

        if index > 0 and not value[index - 1].isspace():
            # Require whitespace before inline comments to avoid stripping
            # legitimate values like "foo#bar".
            continue

        # Count the number of consecutive backslashes directly before the '#'
        # character. An odd number means the hash is escaped and should remain
        # part of the value.
        backslashes = 0
        lookbehind = index - 1
        while lookbehind >= 0 and value[lookbehind] == "\\":
            backslashes += 1
            lookbehind -= 1
        if backslashes % 2 == 1:
            continue

        return index

    return None


def normalize(value: str) -> str:
    value = value.strip()
    if not value:
        return ""

    if value[0] in {'"', "'"}:
        quote = value[0]
        escaped = False
        closing_index: int | None = None
        for index in range(1, len(value)):
            char = value[index]
            if char == "\\" and not escaped:
                escaped = True
                continue
            if escaped:
                escaped = False
                continue
            if char == quote:
                closing_index = index
                break
        if closing_index is not None:
            remainder = value[closing_index + 1 :].strip()
            if not remainder or (
                remainder.startswith('#')
                and (len(remainder) == 1 or remainder[1].isspace())
            ):
                return value[1:closing_index].replace("\\#", "#")

    if value.startswith('#') and (len(value) == 1 or value[1].isspace()):
        return ""

    comment_index = find_comment_index(value)
    if comment_index is not None:
        value = value[:comment_index].rstrip()

    value = value.strip()
    if not value:
        return ""
    if (
        value[0] in {'"', "'"}
        and value[-1] == value[0]
        and len(value) >= 2
    ):
        value = value[1:-1]
    return value.replace("\\#", "#")

def parse_file(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not path.exists():
        return result
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            stripped = raw.strip()
            if not stripped or stripped.startswith('#'):
                continue
            if stripped.startswith('export '):
                stripped = stripped[len('export '):].lstrip()
            if '=' not in stripped:
                continue
            key, value = stripped.split('=', 1)
            key = key.strip()
            if not key:
                continue
            result[key] = normalize(value)
    return result

file_path = Path(sys.argv[1])
requested = sys.argv[2:]
values = parse_file(file_path)

for name in requested:
    if name in values:
        print(f"{name}={values[name]}")
PY
