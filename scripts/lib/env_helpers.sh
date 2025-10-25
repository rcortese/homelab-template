#!/usr/bin/env bash
# Common helpers for environment variable handling in scripts.

_ENV_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_env_pairs() {
  local env_file="$1"
  shift || return 0

  if [[ ! -f "$env_file" ]]; then
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    return 2
  fi

  local output=""
  if ! output="$("${_ENV_HELPERS_DIR}/env_loader.sh" "$env_file" "$@")"; then
    return $?
  fi

  local line key value
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    key="${line%%=*}"
    if [[ -z "$key" ]]; then
      continue
    fi
    if [[ -n "${!key+x}" ]]; then
      continue
    fi
    value="${line#*=}"
    export "$key=$value"
  done <<<"$output"

  return 0
}

