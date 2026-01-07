#!/usr/bin/env bash

# shellcheck source=scripts/lib/compose_paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_paths.sh"

compose_env_map__resolve_instance_env() {
  local repo_root="$1"
  local instance="$2"
  local env_dir_rel="$3"
  local env_local_dir_rel="$4"
  local -n global_env_files="$5"
  local -n env_local_map="$6"
  local -n env_template_map="$7"
  local -n out_env_files_list="$8"

  local env_local_rel="$env_local_dir_rel/${instance}.env"
  local env_local_abs="$repo_root/$env_local_rel"
  local env_template_rel="$env_dir_rel/${instance}.example.env"
  local env_template_abs="$repo_root/$env_template_rel"

  env_local_map["$instance"]=""
  env_template_map["$instance"]=""
  out_env_files_list=("${global_env_files[@]}")

  if [[ ! -f "$env_local_abs" ]]; then
    echo "[!] Missing ${env_local_rel}." >&2
    if [[ -f "$env_template_abs" ]]; then
      echo "    Copy the template before continuing:" >&2
      echo "    mkdir -p ${env_local_dir_rel}" >&2
      echo "    cp ${env_template_rel} ${env_local_rel}" >&2
    else
      echo "    Template ${env_template_rel} was not found." >&2
    fi
    return 1
  fi

  env_local_map["$instance"]="$env_local_rel"
  out_env_files_list+=("$env_local_rel")

  if [[ -f "$env_template_abs" ]]; then
    env_template_map["$instance"]="$env_template_rel"
  fi

  : "${env_local_map[$instance]}" "${env_template_map[$instance]}"

  return 0
}

load_compose_env_map() {
  if ! declare -p COMPOSE_INSTANCE_NAMES >/dev/null 2>&1; then
    echo "[!] COMPOSE_INSTANCE_NAMES not initialized. Run load_compose_discovery first." >&2
    return 1
  fi

  if ! declare -p COMPOSE_INSTANCE_FILES >/dev/null 2>&1; then
    echo "[!] COMPOSE_INSTANCE_FILES not initialized. Run load_compose_discovery first." >&2
    return 1
  fi

  local repo_root
  if ! repo_root="$(compose_common__resolve_repo_root "$1")"; then
    return 1
  fi

  local env_dir_rel="env"
  local env_local_dir_rel="env/local"

  declare -ga COMPOSE_ENV_GLOBAL_FILES=()
  declare -gA COMPOSE_INSTANCE_ENV_LOCAL=()
  declare -gA COMPOSE_INSTANCE_ENV_TEMPLATES=()
  declare -gA COMPOSE_INSTANCE_ENV_FILES=()

  local global_env_local_rel="$env_local_dir_rel/common.env"
  local global_env_template_rel="$env_dir_rel/common.example.env"

  if [[ -f "$repo_root/$global_env_local_rel" ]]; then
    COMPOSE_ENV_GLOBAL_FILES=("$global_env_local_rel")
  else
    echo "[!] Missing ${global_env_local_rel}." >&2
    if [[ -f "$repo_root/$global_env_template_rel" ]]; then
      echo "    Copy the template before continuing:" >&2
      echo "    mkdir -p ${env_local_dir_rel}" >&2
      echo "    cp ${global_env_template_rel} ${global_env_local_rel}" >&2
    else
      echo "    Template ${global_env_template_rel} was not found." >&2
    fi
    return 1
  fi

  local instance
  for instance in "${COMPOSE_INSTANCE_NAMES[@]}"; do
    if [[ ! -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
      echo "[!] Instance '$instance' not found in metadata." >&2
      return 1
    fi

    local -a env_files_list=()
    if ! compose_env_map__resolve_instance_env \
      "$repo_root" \
      "$instance" \
      "$env_dir_rel" \
      "$env_local_dir_rel" \
      COMPOSE_ENV_GLOBAL_FILES \
      COMPOSE_INSTANCE_ENV_LOCAL \
      COMPOSE_INSTANCE_ENV_TEMPLATES \
      env_files_list; then
      return 1
    fi

    if ((${#env_files_list[@]} > 0)); then
      local joined
      local IFS=$'\n'
      printf -v joined '%s' "${env_files_list[*]}"
      COMPOSE_INSTANCE_ENV_FILES[$instance]="$joined"
    else
      COMPOSE_INSTANCE_ENV_FILES[$instance]=""
    fi
  done

  # Touch globals to satisfy shellcheck: consumers read these arrays after sourcing.
  : "${COMPOSE_ENV_GLOBAL_FILES[@]}"
  : "${COMPOSE_INSTANCE_ENV_LOCAL[@]}"
  : "${COMPOSE_INSTANCE_ENV_TEMPLATES[@]}"
  : "${COMPOSE_INSTANCE_ENV_FILES[@]}"

  return 0
}
