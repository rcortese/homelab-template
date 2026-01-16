#!/usr/bin/env bash

# shellcheck source=scripts/_internal/lib/compose_paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_paths.sh"
# shellcheck source=scripts/_internal/lib/env_file_chain.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env_file_chain.sh"

compose_env_map__append_missing_env() {
  local -n missing_block_ref="$1"
  local missing_rel="$2"
  local template_rel="$3"
  local env_local_dir_rel="$4"
  local repo_root="$5"

  local -a lines=()
  lines+=("[!] Missing ${missing_rel}.")
  if [[ -n "$template_rel" && -f "$repo_root/$template_rel" ]]; then
    lines+=("    Copy the template before continuing:")
    lines+=("    mkdir -p ${env_local_dir_rel}")
    lines+=("    cp ${template_rel} ${missing_rel}")
  else
    lines+=("    Template ${template_rel} was not found.")
  fi

  local line
  for line in "${lines[@]}"; do
    if [[ -z "$missing_block_ref" ]]; then
      missing_block_ref="$line"
    else
      missing_block_ref+=$'\n'"$line"
    fi
  done
}

compose_env_map__resolve_instance_env() {
  local repo_root="$1"
  local instance="$2"
  local env_dir_rel="$3"
  local env_local_dir_rel="$4"
  local -n global_env_files="$5"
  local -n env_local_map="$6"
  local -n env_template_map="$7"
  local -n out_env_files_list="$8"
  local missing_block_ref="$9"

  local env_local_rel="$env_local_dir_rel/${instance}.env"
  local env_local_abs="$repo_root/$env_local_rel"
  local env_template_rel="$env_dir_rel/${instance}.example.env"
  local env_template_abs="$repo_root/$env_template_rel"

  env_local_map["$instance"]=""
  env_template_map["$instance"]=""
  out_env_files_list=("${global_env_files[@]}")

  if [[ ! -f "$env_local_abs" ]]; then
    compose_env_map__append_missing_env \
      "$missing_block_ref" \
      "$env_local_rel" \
      "$env_template_rel" \
      "$env_local_dir_rel" \
      "$repo_root"
    return 1
  fi

  env_local_map["$instance"]="$env_local_rel"
  local already_listed=false
  local entry
  for entry in "${out_env_files_list[@]}"; do
    if [[ "$entry" == "$env_local_rel" ]]; then
      already_listed=true
      break
    fi
  done
  if [[ "$already_listed" == false ]]; then
    out_env_files_list+=("$env_local_rel")
  fi

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

  local instance_filter="${2:-}"
  local -a instance_filters=()
  declare -A instance_filter_map=()
  if [[ -n "$instance_filter" ]]; then
    mapfile -t instance_filters < <(env_file_chain__parse_list "$instance_filter")
    if ((${#instance_filters[@]} == 0)); then
      echo "[!] Instance filter did not include any instances." >&2
      return 1
    fi
    local filter_instance
    for filter_instance in "${instance_filters[@]}"; do
      if [[ ! -v COMPOSE_INSTANCE_FILES[$filter_instance] ]]; then
        echo "[!] Instance '$filter_instance' not found in metadata." >&2
        return 1
      fi
      instance_filter_map["$filter_instance"]=1
    done
  fi

  local env_dir_rel="env"
  local env_local_dir_rel="env/local"

  declare -ga COMPOSE_ENV_GLOBAL_FILES=()
  declare -gA COMPOSE_INSTANCE_ENV_LOCAL=()
  declare -gA COMPOSE_INSTANCE_ENV_TEMPLATES=()
  declare -gA COMPOSE_INSTANCE_ENV_FILES=()

  local global_env_local_rel="$env_local_dir_rel/common.env"
  local global_env_template_rel="$env_dir_rel/common.example.env"
  local missing=0
  local missing_block=""

  if [[ -f "$repo_root/$global_env_local_rel" ]]; then
    COMPOSE_ENV_GLOBAL_FILES=("$global_env_local_rel")
  else
    compose_env_map__append_missing_env \
      missing_block \
      "$global_env_local_rel" \
      "$global_env_template_rel" \
      "$env_local_dir_rel" \
      "$repo_root"
    missing=1
  fi

  local instance
  for instance in "${COMPOSE_INSTANCE_NAMES[@]}"; do
    if [[ ! -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
      echo "[!] Instance '$instance' not found in metadata." >&2
      return 1
    fi

    if ((${#instance_filters[@]} > 0)) && [[ -z "${instance_filter_map[$instance]:-}" ]]; then
      COMPOSE_INSTANCE_ENV_LOCAL["$instance"]=""
      COMPOSE_INSTANCE_ENV_TEMPLATES["$instance"]=""
      COMPOSE_INSTANCE_ENV_FILES["$instance"]=""
      continue
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
      env_files_list \
      missing_block; then
      missing=1
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

  if ((missing == 1)); then
    printf '%s\n' "$missing_block" >&2
    return 1
  fi

  # Touch globals to satisfy shellcheck: consumers read these arrays after sourcing.
  : "${COMPOSE_ENV_GLOBAL_FILES[@]}"
  : "${COMPOSE_INSTANCE_ENV_LOCAL[@]}"
  : "${COMPOSE_INSTANCE_ENV_TEMPLATES[@]}"
  : "${COMPOSE_INSTANCE_ENV_FILES[@]}"

  return 0
}
