#!/usr/bin/env bash

# shellcheck source=./compose_discovery.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_discovery.sh"

# shellcheck source=./compose_env_map.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_env_map.sh"

load_compose_instances() {
  local repo_root_input="${1:-}"

  if ! load_compose_discovery "$repo_root_input"; then
    return 1
  fi

  if ! load_compose_env_map "$repo_root_input"; then
    return 1
  fi

  return 0
}

print_compose_instances() {
  local repo_root_input="${1:-}"

  if ! load_compose_instances "$repo_root_input"; then
    return 1
  fi

  declare -p \
    BASE_COMPOSE_FILE \
    COMPOSE_INSTANCE_NAMES \
    COMPOSE_INSTANCE_FILES \
    COMPOSE_INSTANCE_ENV_LOCAL \
    COMPOSE_INSTANCE_ENV_TEMPLATES \
    COMPOSE_INSTANCE_ENV_FILES \
    COMPOSE_INSTANCE_APP_NAMES
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  print_compose_instances "$@"
fi
