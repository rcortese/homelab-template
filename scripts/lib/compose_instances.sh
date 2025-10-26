#!/usr/bin/env bash

# shellcheck source=./compose_discovery.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_discovery.sh"

# shellcheck source=./compose_env_map.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_env_map.sh"

load_compose_instances() {
  local repo_root_input="${1:-}"
  local repo_root

  if [[ -n "$repo_root_input" ]]; then
    if ! repo_root="$(cd "$repo_root_input" 2>/dev/null && pwd)"; then
      echo "[!] Diretório do repositório inválido: $repo_root_input" >&2
      return 1
    fi
  else
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi

  if ! load_compose_discovery "$repo_root"; then
    return 1
  fi

  if ! load_env_map "$repo_root"; then
    return 1
  fi

  return 0
}

print_compose_instances() {
  if ! load_compose_instances "$@"; then
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
