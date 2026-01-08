#!/usr/bin/env bash
# Usage: scripts/check_all.sh [--with-quality-checks]
# Runs the core validation sequence for the template.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check_all.sh [--with-quality-checks]

Runs the core validation sequence for the template. Use
--with-quality-checks to invoke scripts/run_quality_checks.sh after
validate_compose.sh.
EOF
}

RUN_QUALITY_CHECKS=0

while (($# > 0)); do
  case "$1" in
  --with-quality-checks)
    RUN_QUALITY_CHECKS=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/check_structure.sh"
"${SCRIPT_DIR}/check_env_sync.sh"
"${SCRIPT_DIR}/validate_env_output.sh"
"${SCRIPT_DIR}/validate_compose.sh"

if ((RUN_QUALITY_CHECKS)); then
  "${SCRIPT_DIR}/run_quality_checks.sh"
fi
