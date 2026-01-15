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

# shellcheck source=_internal/lib/compose_paths.sh
source "$SCRIPT_DIR/_internal/lib/compose_paths.sh"

if ! REPO_ROOT="$(compose_common__resolve_repo_root)"; then
  exit 1
fi

"${REPO_ROOT}/scripts/check_structure.sh"
"${REPO_ROOT}/scripts/check_env_sync.sh"
"${REPO_ROOT}/scripts/validate_env_output.sh"
"${REPO_ROOT}/scripts/validate_compose.sh"

if ((RUN_QUALITY_CHECKS)); then
  "${REPO_ROOT}/scripts/run_quality_checks.sh"
fi
