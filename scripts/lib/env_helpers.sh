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

resolve_app_data_dir_mount() {
  local input_value="${1:-}"

  if [[ -z "$input_value" ]]; then
    printf '%s' ""
    return 0
  fi

  if [[ "$input_value" == /* ]]; then
    printf '%s' "$input_value"
    return 0
  fi

  local sanitized="$input_value"
  while [[ "$sanitized" == ./* ]]; do
    sanitized="${sanitized#./}"
  done

  if [[ "$sanitized" == ..* ]]; then
    printf '%s' "$sanitized"
    return 0
  fi

  printf '../%s' "$sanitized"
}
