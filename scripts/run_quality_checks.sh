#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/run_quality_checks.sh [--no-lint]
#
# Runs the standard suite of tests and linters for the template.
# The routine validates Python code via ``pytest`` and executes ``shfmt``,
# ``shellcheck``, and ``checkbashisms`` across automation scripts. It fails
# immediately if any step returns a non-zero status.
#
# Example:
#   scripts/run_quality_checks.sh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_quality_checks.sh [--no-lint]

Runs ``pytest`` and applies ``shfmt``/``shellcheck``/``checkbashisms`` to the template.

Options:
  --no-lint    Skips the linting step via ``shfmt``/``shellcheck``/``checkbashisms``.
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
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SHELLCHECK_BIN="${SHELLCHECK_BIN:-shellcheck}"
SHFMT_BIN="${SHFMT_BIN:-shfmt}"
CHECKBASHISMS_BIN="${CHECKBASHISMS_BIN:-checkbashisms}"
SHELLCHECK_OPTS="${SHELLCHECK_OPTS:--x -P scripts}"
export SHELLCHECK_OPTS

PYTHON_HELPERS_PATH="${SCRIPT_DIR}/lib/python_runtime.sh"

if [[ -f "$PYTHON_HELPERS_PATH" ]]; then
  # shellcheck source=lib/python_runtime.sh
  source "$PYTHON_HELPERS_PATH"

  run_pytest() {
    python_runtime__run "$REPO_ROOT" "" -- -m pytest "$@"
  }
else
  run_pytest() {
    local python_bin
    python_bin="${PYTHON_BIN:-python}"
    "${python_bin}" -m pytest "$@"
  }
fi

require_command() {
  local tool="$1"
  local bin="$2"
  local env_var="$3"

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: dependency '${tool}' not found (tried to use '${bin}'). Install the binary or set ${env_var}." >&2
    exit 1
  fi
}

if ((RUN_LINT)); then
  require_command "shfmt" "${SHFMT_BIN}" "SHFMT_BIN"
  require_command "shellcheck" "${SHELLCHECK_BIN}" "SHELLCHECK_BIN"
  require_command "checkbashisms" "${CHECKBASHISMS_BIN}" "CHECKBASHISMS_BIN"
fi

# Runs the template's Python test suite.
cd "${REPO_ROOT}"
run_pytest "$@"

if ((RUN_LINT)); then
  # Prepares the list of shell scripts for linting.
  mapfile -d '' -t raw_shellcheck_targets < <(
    find "${SCRIPT_DIR}" -type f -name '*.sh' -printf '%d\t%p\0' |
      sort -z -t $'\t' -k1,1n -k2,2
  )

  shellcheck_targets=()
  for entry in "${raw_shellcheck_targets[@]}"; do
    shellcheck_targets+=("${entry#*$'\t'}")
  done

  if ((${#shellcheck_targets[@]} > 0)); then
    shfmt_diff="$("${SHFMT_BIN}" -d "${shellcheck_targets[@]}")"
    if [[ -n "${shfmt_diff}" ]]; then
      printf '%s\n' "${shfmt_diff}"
      exit 1
    fi
    "${SHELLCHECK_BIN}" "${shellcheck_targets[@]}"
    "${CHECKBASHISMS_BIN}" "${shellcheck_targets[@]}"
  fi
fi
