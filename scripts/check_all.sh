#!/usr/bin/env bash
# Usage: scripts/check_all.sh
#
# Runs the default sequence of local validations for the template.
# Chains the essential scripts in the recommended order and stops
# immediately if any of them fails.
#
# Examples:
#   scripts/check_all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/check_structure.sh"
"${SCRIPT_DIR}/check_env_sync.sh"
"${SCRIPT_DIR}/validate_compose.sh"
