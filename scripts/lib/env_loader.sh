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
import sys
from pathlib import Path

def normalize(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if value[0] in {'"', "'"} and value[-1] == value[0] and len(value) >= 2:
        value = value[1:-1]
    if value and value[0] not in {'"', "'"}:
        if ' #' in value:
            value = value.split(' #', 1)[0].rstrip()
        elif value.startswith('#'):
            return ""
    return value

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
