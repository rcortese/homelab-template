#!/usr/bin/env bash
set -euo pipefail

COMPOSE_MOUNTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/_internal/lib/python_runtime.sh
source "${COMPOSE_MOUNTS_DIR}/python_runtime.sh"

compose_mounts__collect_bind_paths() {
  local repo_root="$1"
  shift
  local -a compose_files=("$@")

  if ((${#compose_files[@]} == 0)); then
    return 0
  fi

  local script_path="${COMPOSE_MOUNTS_DIR}/../python/collect_bind_mounts.py"

  REPO_ROOT="$repo_root" \
    python_runtime__run "$repo_root" "REPO_ROOT" -- "$script_path" "${compose_files[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This script is intended to be sourced." >&2
  exit 1
fi
