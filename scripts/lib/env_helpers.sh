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

_env_helpers__strip_leading_dot_slash() {
  local value="$1"
  while [[ "$value" == ./* ]]; do
    value="${value#./}"
  done
  printf '%s' "$value"
}

_env_helpers__normalize_base_input() {
  local value="$1"
  value="${value%/}"
  value="$(_env_helpers__strip_leading_dot_slash "$value")"
  printf '%s' "$value"
}

_env_helpers__to_absolute_path() {
  local repo_root="$1"
  local value="$2"

  python3 - "$repo_root" "$value" <<'PY'
import os
import sys

repo_root = sys.argv[1]
value = sys.argv[2]

if not value:
    print("")
    raise SystemExit(0)

if os.path.isabs(value):
    print(os.path.normpath(value))
else:
    print(os.path.normpath(os.path.join(repo_root, value)))
PY
}

normalize_app_data_dir_inputs() {
  if [[ $# -lt 6 ]]; then
    echo "normalize_app_data_dir_inputs: parâmetros obrigatórios ausentes." >&2
    return 64
  fi

  local repo_root="$1"
  local service_name="$2"
  local base_input="$3"
  local mount_input="$4"
  local base_var="$5"
  local mount_var="$6"

  if [[ -z "$repo_root" || -z "$service_name" ]]; then
    echo "normalize_app_data_dir_inputs: parâmetros obrigatórios ausentes." >&2
    return 64
  fi

  local -n __base_out=$base_var
  local -n __mount_out=$mount_var

  __base_out=""
  __mount_out=""

  local sanitized_base=""
  local sanitized_mount_override=""
  if [[ -n "$base_input" ]]; then
    sanitized_base="$(_env_helpers__normalize_base_input "$base_input")"
  fi

  if [[ -n "$mount_input" ]]; then
    sanitized_mount_override="$(_env_helpers__normalize_base_input "$mount_input")"
  fi

  if [[ -n "$sanitized_base" && -n "$sanitized_mount_override" ]]; then
    echo "Error: APP_DATA_DIR e APP_DATA_DIR_MOUNT são mutuamente exclusivos." >&2
    return 65
  fi

  local derived_base="$sanitized_base"
  local absolute_mount=""

  if [[ -n "$sanitized_base" ]]; then
    absolute_mount="$(_env_helpers__to_absolute_path "$repo_root" "$sanitized_base")"
    absolute_mount="${absolute_mount%/}/$service_name"
  elif [[ -n "$sanitized_mount_override" ]]; then
    absolute_mount="$(_env_helpers__to_absolute_path "$repo_root" "$sanitized_mount_override")"
    absolute_mount="${absolute_mount%/}"
    if [[ -z "$absolute_mount" ]]; then
      __base_out=""
      __mount_out=""
      return 0
    fi
    if [[ "${absolute_mount##*/}" != "$service_name" ]]; then
      absolute_mount="$absolute_mount/$service_name"
    fi

    local parent_dir="${absolute_mount%/*}"
    if [[ "$parent_dir" == "$repo_root" ]]; then
      derived_base=""
    elif [[ "$parent_dir" == "$repo_root/"* ]]; then
      derived_base="${parent_dir#${repo_root}/}"
    else
      derived_base="$parent_dir"
    fi
  else
    derived_base=""
    absolute_mount=""
  fi

  __base_out="$derived_base"
  __mount_out="$absolute_mount"
  return 0
}
