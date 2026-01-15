#!/usr/bin/env bash
# Usage: scripts/check_structure.sh
#
# Arguments:
#   (none) — the script always validates the current repository tree.
# Environment:
#   CI (optional): can be used in pipelines to indicate automated runs.
# Examples:
#   scripts/check_structure.sh
set -euo pipefail

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Usage: scripts/check_structure.sh

Validates that the required repository directories and files exist.

Positional arguments:
  (none)

Relevant environment variables:
  CI  Optional, can be used to differentiate pipeline runs.

Example:
  scripts/check_structure.sh
EOF
  exit 0
  ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_internal/lib/compose_paths.sh
source "$SCRIPT_DIR/_internal/lib/compose_paths.sh"

if ! ROOT_DIR_DEFAULT="$(compose_common__resolve_repo_root)"; then
  exit 1
fi
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
    printf 'Unknown type %s for %s\n' "$expected_type" "$path" >&2
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
  printf '\nError: the following required items were not found:\n' >&2
  for path in "${missing[@]}"; do
    printf '  - %s\n' "$path" >&2
  done
  printf '\nSee docs/STRUCTURE.md for details about the required structure.\n' >&2
  exit 1
fi

printf 'Repository structure validated successfully.\n'
