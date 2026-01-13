#!/usr/bin/env bash

# shellcheck source=scripts/_internal/lib/compose_discovery.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_discovery.sh"

# shellcheck source=scripts/_internal/lib/compose_env_map.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_env_map.sh"

load_compose_instances() {
  local repo_root_input="${1:-}"
  local instance_filter="${2:-}"

  if ! load_compose_discovery "$repo_root_input"; then
    return 1
  fi

  if ! load_compose_env_map "$repo_root_input" "$instance_filter"; then
    return 1
  fi

  return 0
}

print_compose_instances() {
  local repo_root_input="${1:-}"
  local instance_filter="${2:-}"

  if ! load_compose_instances "$repo_root_input" "$instance_filter"; then
    return 1
  fi

  declare -p \
    BASE_COMPOSE_FILE \
    COMPOSE_INSTANCE_NAMES \
    COMPOSE_INSTANCE_FILES \
    COMPOSE_INSTANCE_ENV_LOCAL \
    COMPOSE_INSTANCE_ENV_TEMPLATES \
    COMPOSE_INSTANCE_ENV_FILES
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  print_compose_instances "$@"
fi
