#!/usr/bin/env bash
# Usage: scripts/run_quality_checks.sh [--no-lint]
#
# Executa a bateria padrão de testes e linters do template.
# A rotina valida código Python via ``pytest`` e executa ``shfmt`` e
# ``shellcheck`` sobre os scripts de automação. Falha imediatamente se qualquer etapa
# retornar código diferente de zero.
#
# Exemplo:
#   scripts/run_quality_checks.sh
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: scripts/run_quality_checks.sh [--no-lint]

Executa ``pytest`` e aplica ``shfmt``/``shellcheck`` sobre o template.

Opções:
  --no-lint    Pula a etapa de linting via ``shfmt``/``shellcheck``.
EOF
}

RUN_LINT=1

while (($# > 0)); do
  case "$1" in
  --no-lint)
    RUN_LINT=0
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Argumento desconhecido: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python}"
SHELLCHECK_BIN="${SHELLCHECK_BIN:-shellcheck}"
SHFMT_BIN="${SHFMT_BIN:-shfmt}"

# Executa a suíte de testes Python do template.
cd "${REPO_ROOT}"
"${PYTHON_BIN}" -m pytest

if ((RUN_LINT)); then
  # Prepara a lista de scripts shell para lint.
  shopt -s nullglob
  shell_scripts=("${SCRIPT_DIR}"/*.sh)
  lib_scripts=("${SCRIPT_DIR}/lib"/*.sh)
  shopt -u nullglob

  shellcheck_targets=("${shell_scripts[@]}" "${lib_scripts[@]}")

  if ((${#shellcheck_targets[@]} > 0)); then
    "${SHFMT_BIN}" -d "${shellcheck_targets[@]}"
    "${SHELLCHECK_BIN}" "${shellcheck_targets[@]}"
  fi
fi
