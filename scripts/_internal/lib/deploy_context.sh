#!/usr/bin/env bash

_DEPLOY_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/_internal/lib/compose_plan.sh
source "${_DEPLOY_CONTEXT_DIR}/compose_plan.sh"

# shellcheck source=scripts/_internal/lib/compose_env_chain.sh
source "${_DEPLOY_CONTEXT_DIR}/compose_env_chain.sh"

# shellcheck source=scripts/_internal/lib/env_file_chain.sh
source "${_DEPLOY_CONTEXT_DIR}/env_file_chain.sh"

# shellcheck source=scripts/_internal/lib/compose_mounts.sh
source "${_DEPLOY_CONTEXT_DIR}/compose_mounts.sh"

load_deploy_metadata() {
  local repo_root="$1"
  local instance_filter="${2:-}"

  if [[ -n "${DEPLOY_METADATA_LOADED:-}" && "${DEPLOY_METADATA_INSTANCE_FILTER:-}" == "$instance_filter" ]]; then
    return 0
  fi

  local compose_metadata=""
  if ! compose_metadata="$("${_DEPLOY_CONTEXT_DIR}/compose_instances.sh" "$repo_root" "$instance_filter" | sed 's/^declare /declare -g /')"; then
    echo "[!] Failed to load instance metadata." >&2
    return 1
  fi

  eval "$compose_metadata"
  DEPLOY_METADATA_LOADED=1
  DEPLOY_METADATA_INSTANCE_FILTER="$instance_filter"
  return 0
}

deploy_context__report_missing_instance() {
  local repo_root="$1"
  local instance="$2"
  shift 2
  local available_instances=("$@")

  echo "[!] Invalid instance '$instance'." >&2

  if ((${#available_instances[@]} > 0)); then
    echo "    Available: ${available_instances[*]}" >&2
  fi

  return 1
}

build_deploy_context() {
  local repo_root="$1"
  local instance="$2"

  if ! load_deploy_metadata "$repo_root" "$instance"; then
    return 1
  fi

  local known_instance=""
  local found_instance=0
  for known_instance in "${COMPOSE_INSTANCE_NAMES[@]}"; do
    if [[ "$known_instance" == "$instance" ]]; then
      found_instance=1
      break
    fi
  done

  if [[ $found_instance -eq 0 ]]; then
    deploy_context__report_missing_instance "$repo_root" "$instance" "${COMPOSE_INSTANCE_NAMES[@]}"
    return 1
  fi

  if [[ ! -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
    deploy_context__report_missing_instance "$repo_root" "$instance" "${COMPOSE_INSTANCE_NAMES[@]}"
    return 1
  fi

  local local_env_file=""
  if [[ -v COMPOSE_INSTANCE_ENV_LOCAL["$instance"] ]]; then
    local_env_file="${COMPOSE_INSTANCE_ENV_LOCAL[$instance]}"
  fi

  local template_file=""
  if [[ -v COMPOSE_INSTANCE_ENV_TEMPLATES["$instance"] ]]; then
    template_file="${COMPOSE_INSTANCE_ENV_TEMPLATES[$instance]}"
  fi

  if [[ -z "$local_env_file" ]]; then
    local template_display="${template_file:-env/${instance}.example.env}"

    if [[ -n "$template_file" && -f "$repo_root/$template_file" ]]; then
      echo "[!] File env/local/${instance}.env not found." >&2
      echo "    Copy the default template before continuing:" >&2
      echo "    mkdir -p env/local" >&2
      echo "    cp ${template_file} env/local/${instance}.env" >&2
    else
      echo "[!] No .env file was found for instance '$instance'." >&2
      echo "    Expected: env/local/${instance}.env or ${template_display}" >&2
    fi
    return 1
  fi

  local env_files_blob=""
  if [[ -v COMPOSE_INSTANCE_ENV_FILES["$instance"] ]]; then
    env_files_blob="${COMPOSE_INSTANCE_ENV_FILES[$instance]}"
  fi

  declare -a env_files_rel=()
  declare -a env_files_abs=()
  local -a requested_env_keys=(
    COMPOSE_EXTRA_FILES
    APP_DATA_UID
    APP_DATA_GID
    REPO_ROOT
    LOCAL_INSTANCE
    APP_DATA_DIR
    APP_DATA_DIR_MOUNT
  )
  local -A loaded_env_values=()
  if ! compose_env_chain__prepare \
    "$_DEPLOY_CONTEXT_DIR" \
    "$repo_root" \
    "$instance" \
    "$env_files_blob" \
    env_files_rel \
    env_files_abs \
    loaded_env_values \
    requested_env_keys \
    "[!] REPO_ROOT must not be set in env files; it is derived by scripts." \
    "[!] LOCAL_INSTANCE is derived by scripts and must not be set in env files." \
    "[!] APP_DATA_DIR and APP_DATA_DIR_MOUNT are no longer supported." \
    ""; then
    return 1
  fi

  local idx=0
  while ((idx < ${#env_files_rel[@]})); do
    local rel_entry="${env_files_rel[$idx]}"
    local abs_entry="${env_files_abs[$idx]}"

    if [[ ! -f "$abs_entry" ]]; then
      echo "[!] File ${rel_entry} not found." >&2
      if [[ "$rel_entry" == "$local_env_file" ]]; then
        if [[ -n "$template_file" && -f "$repo_root/$template_file" ]]; then
          echo "    Copy the default template before continuing:" >&2
          echo "    cp ${template_file} ${rel_entry}" >&2
        elif [[ -n "$template_file" ]]; then
          echo "    Matching template (${template_file}) was not found either." >&2
        fi
      fi
      return 1
    fi

    idx=$((idx + 1))
  done

  local key
  for key in "${requested_env_keys[@]}"; do
    if [[ -n "${loaded_env_values[$key]+x}" ]]; then
      if [[ "$key" == "COMPOSE_EXTRA_FILES" && -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
        continue
      fi
      if [[ "$key" == "REPO_ROOT" || "$key" == "LOCAL_INSTANCE" || "$key" == "APP_DATA_DIR" || "$key" == "APP_DATA_DIR_MOUNT" ]]; then
        continue
      fi
      export "$key=${loaded_env_values[$key]}"
    fi
  done

  local primary_app="$instance"
  local app_names_string=""
  local app_data_rel=""
  if [[ -n "$primary_app" && -n "$instance" ]]; then
    app_data_rel="data/${instance}/app"
  fi

  local app_data_path="$repo_root/$app_data_rel"

  local -a extra_compose_files=()
  local extra_compose_files_string=""
  if [[ -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
    IFS=$' \t\n' read -r -a extra_compose_files <<<"${COMPOSE_EXTRA_FILES//,/ }"
    if ((${#extra_compose_files[@]} > 0)); then
      extra_compose_files_string="$(printf '%s\n' "${extra_compose_files[@]}")"
      extra_compose_files_string="${extra_compose_files_string%$'\n'}"
    fi
  fi

  local -a compose_files_list=()
  if ! build_compose_file_plan "$instance" compose_files_list extra_compose_files; then
    echo "[!] Failed to assemble Compose file list for '$instance'." >&2
    return 1
  fi

  local -a compose_files_abs=()
  local compose_file
  for compose_file in "${compose_files_list[@]}"; do
    if [[ "$compose_file" == /* ]]; then
      compose_files_abs+=("$compose_file")
    else
      compose_files_abs+=("$repo_root/${compose_file#./}")
    fi
  done

  local compose_files_string="${compose_files_list[*]}"

  local env_files_string=""
  if [[ ${#env_files_rel[@]} -gt 0 ]]; then
    env_files_string="$(env_file_chain__join "," "${env_files_rel[@]}")"
  fi

  local -a bind_mount_dirs=()
  local bind_mounts_raw=""
  if bind_mounts_raw="$(compose_mounts__collect_bind_paths "$repo_root" "${compose_files_abs[@]}")"; then
    if [[ -n "$bind_mounts_raw" ]]; then
      mapfile -t bind_mount_dirs <<<"$bind_mounts_raw"
    fi
  else
    echo "[!] Warning: failed to parse bind mounts from the compose plan." >&2
  fi

  local -a persistent_dirs=("$app_data_path" "$repo_root/backups")
  local bind_dir
  for bind_dir in "${bind_mount_dirs[@]}"; do
    append_unique_file persistent_dirs "$bind_dir"
  done
  local persistent_dirs_string
  persistent_dirs_string="$(printf '%s\n' "${persistent_dirs[@]}")"

  local data_uid="${APP_DATA_UID:-1000}"
  local data_gid="${APP_DATA_GID:-1000}"
  local app_data_uid_gid="${data_uid}:${data_gid}"

  printf 'declare -A DEPLOY_CONTEXT=(\n'
  printf '  [INSTANCE]=%q\n' "$instance"
  printf '  [COMPOSE_ENV_FILES]=%q\n' "$env_files_string"
  printf '  [COMPOSE_EXTRA_FILES]=%q\n' "$extra_compose_files_string"
  printf '  [COMPOSE_FILES]=%q\n' "$compose_files_string"
  printf '  [APP_DATA_REL]=%q\n' "$app_data_rel"
  printf '  [APP_DATA_PATH]=%q\n' "$app_data_path"
  printf '  [PERSISTENT_DIRS]=%q\n' "$persistent_dirs_string"
  printf '  [DATA_UID]=%q\n' "$data_uid"
  printf '  [DATA_GID]=%q\n' "$data_gid"
  printf '  [APP_DATA_UID_GID]=%q\n' "$app_data_uid_gid"
  printf '  [APP_NAMES]=%q\n' "$app_names_string"
  printf ')\n'
}
