#!/usr/bin/env bash
# Usage: scripts/check_all.sh
#
# Executa a sequência padrão de validações locais do template.
# Encadeia os scripts essenciais na ordem recomendada e encerra
# imediatamente se algum deles falhar.
#
# Exemplos:
#   scripts/check_all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/check_structure.sh"
"${SCRIPT_DIR}/check_env_sync.py"
"${SCRIPT_DIR}/validate_compose.sh"
