#!/usr/bin/env bash
set -euo pipefail

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

python3 - "$ENV_FILE" "$@" <<'PY'
import re
import sys
from pathlib import Path

COMMENT_PATTERN = re.compile(r"(?<!\\)\s+#")


def normalize(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    was_quoted = (
        value[0] in {'"', "'"}
        and value[-1] == value[0]
        and len(value) >= 2
    )
    if was_quoted:
        value = value[1:-1]
    if value and not was_quoted:
        match = COMMENT_PATTERN.search(value)
        if match:
            value = value[: match.start()].rstrip()
        elif value.startswith('#') and (len(value) == 1 or value[1].isspace()):
            return ""
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
