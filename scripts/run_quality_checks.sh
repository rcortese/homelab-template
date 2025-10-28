#!/usr/bin/env bash
# Usage: scripts/run_quality_checks.sh [--no-lint]
#
# Executa a bateria padrão de testes e linters do template.
# A rotina valida código Python via ``pytest`` e executa ``shfmt``,
# ``shellcheck`` e ``checkbashisms`` sobre os scripts de automação. Falha imediatamente se qualquer etapa
# retornar código diferente de zero.
#
# Exemplo:
#   scripts/run_quality_checks.sh
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: scripts/run_quality_checks.sh [--no-lint]

Executa ``pytest`` e aplica ``shfmt``/``shellcheck``/``checkbashisms`` sobre o template.

Opções:
  --no-lint    Pula a etapa de linting via ``shfmt``/``shellcheck``/``checkbashisms``.
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
CHECKBASHISMS_BIN="${CHECKBASHISMS_BIN:-checkbashisms}"

require_command() {
  local tool="$1"
  local bin="$2"
  local env_var="$3"

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Erro: dependência '${tool}' não encontrada (tentou usar '${bin}'). Instale o binário ou defina ${env_var}." >&2
    exit 1
  fi
}

require_command "python" "${PYTHON_BIN}" "PYTHON_BIN"

if ((RUN_LINT)); then
  require_command "shfmt" "${SHFMT_BIN}" "SHFMT_BIN"
  require_command "shellcheck" "${SHELLCHECK_BIN}" "SHELLCHECK_BIN"
  require_command "checkbashisms" "${CHECKBASHISMS_BIN}" "CHECKBASHISMS_BIN"
fi

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
    shfmt_diff_found=0
    shfmt_output=""

    set +e
    shfmt_output="$("${SHFMT_BIN}" -d "${shellcheck_targets[@]}")"
    shfmt_status=$?
    set -e

    if ((shfmt_status != 0)); then
      if [[ -n "${shfmt_output}" ]]; then
        printf '%s\n' "${shfmt_output}"
      fi
      exit "${shfmt_status}"
    fi

    if [[ -n "${shfmt_output}" ]]; then
      printf '%s\n' "${shfmt_output}"
      shfmt_diff_found=1
    fi

    "${SHELLCHECK_BIN}" "${shellcheck_targets[@]}"
    "${CHECKBASHISMS_BIN}" "${shellcheck_targets[@]}"

    if ((shfmt_diff_found)); then
      echo "Erro: shfmt encontrou diferenças de formatação." >&2
      exit 1
    fi
  fi
fi
