#!/usr/bin/env bash

if [[ -z "${COMPOSE_PATHS_LIB_DIR:-}" ]]; then
  COMPOSE_PATHS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly COMPOSE_PATHS_LIB_DIR
fi

compose_common__resolve_repo_root() {
  local repo_root_input="${1:-}"

  if [[ -n "$repo_root_input" ]]; then
    if ! (cd "$repo_root_input" 2>/dev/null); then
      echo "[!] Diretório do repositório inválido: $repo_root_input" >&2
      return 1
    fi
    (cd "$repo_root_input" && pwd)
    return 0
  fi

  (cd "$COMPOSE_PATHS_LIB_DIR/../.." && pwd)
}
