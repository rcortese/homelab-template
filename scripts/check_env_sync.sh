#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/python_runtime.sh
source "${SCRIPT_DIR}/lib/python_runtime.sh"

python_runtime__run "$REPO_ROOT" "" -- "${SCRIPT_DIR}/check_env_sync.py" "$@"
