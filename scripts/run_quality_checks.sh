#!/usr/bin/env bash
# Usage: scripts/run_quality_checks.sh
#
# Executa a bateria padrão de testes e linters do template.
# A rotina valida código Python via ``pytest`` e executa ``shellcheck``
# sobre os scripts de automação. Falha imediatamente se qualquer etapa
# retornar código diferente de zero.
#
# Exemplo:
#   scripts/run_quality_checks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python}"
SHELLCHECK_BIN="${SHELLCHECK_BIN:-shellcheck}"

# Executa a suíte de testes Python do template.
cd "${REPO_ROOT}"
"${PYTHON_BIN}" -m pytest

# Prepara a lista de scripts shell para lint.
shopt -s nullglob
shell_scripts=("${SCRIPT_DIR}"/*.sh)
lib_scripts=("${SCRIPT_DIR}/lib"/*.sh)
shopt -u nullglob

shellcheck_targets=("${shell_scripts[@]}" "${lib_scripts[@]}")

if ((${#shellcheck_targets[@]} > 0)); then
    "${SHELLCHECK_BIN}" "${shellcheck_targets[@]}"
fi
