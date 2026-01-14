#!/usr/bin/env bash
# Compose YAML validation helpers.
set -euo pipefail

COMPOSE_YAML_VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/_internal/lib/python_runtime.sh
source "$COMPOSE_YAML_VALIDATION_DIR/python_runtime.sh"

compose_yaml_validate_services_mapping() {
  local repo_root="$1"
  shift

  local -a files=("$@")
  if ((${#files[@]} == 0)); then
    return 0
  fi

  local script_path="$repo_root/scripts/_internal/python/validate_compose_yaml.py"
  python_runtime__run "$repo_root" "" -- "$script_path" "${files[@]}"
}
