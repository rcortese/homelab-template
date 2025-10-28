#!/usr/bin/env bash
# Usage: scripts/check_structure.sh
#
# Arguments:
#   (nenhum) — o script sempre valida a árvore do repositório atual.
# Environment:
#   CI (opcional): pode ser usado em pipelines para indicar execução automatizada.
# Examples:
#   scripts/check_structure.sh
set -euo pipefail

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Uso: scripts/check_structure.sh

Valida se os diretórios e arquivos obrigatórios do repositório existem.

Argumentos posicionais:
  (nenhum)

Variáveis de ambiente relevantes:
  CI  Opcional, pode ser usado para diferenciar execuções em pipelines.

Exemplo:
  scripts/check_structure.sh
EOF
  exit 0
  ;;
esac

ROOT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="${ROOT_DIR_OVERRIDE:-$ROOT_DIR_DEFAULT}"
cd "$ROOT_DIR"

missing=()

require_path() {
  local path="$1"
  local expected_type="$2"

  case "$expected_type" in
  dir)
    if [[ ! -d "$path" ]]; then
      missing+=("$path")
    fi
    ;;
  file)
    if [[ ! -f "$path" ]]; then
      missing+=("$path")
    fi
    ;;
  *)
    printf 'Tipo desconhecido %s para %s\n' "$expected_type" "$path" >&2
    exit 1
    ;;
  esac
}

for dir in \
  "compose" \
  "env" \
  "scripts" \
  "docs" \
  "tests" \
  ".github/workflows"; do
  require_path "$dir" dir
done

for file in \
  "README.md" \
  "docs/STRUCTURE.md" \
  "scripts/check_structure.sh" \
  "scripts/validate_compose.sh" \
  ".github/workflows/template-quality.yml"; do
  require_path "$file" file
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '\nErro: os itens a seguir são obrigatórios e não foram encontrados:\n' >&2
  for path in "${missing[@]}"; do
    printf '  - %s\n' "$path" >&2
  done
  printf '\nConsulte docs/STRUCTURE.md para os detalhes da estrutura exigida.\n' >&2
  exit 1
fi

printf 'Estrutura do repositório validada com sucesso.\n'
