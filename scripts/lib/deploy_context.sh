#!/usr/bin/env bash

_DEPLOY_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/env_helpers.sh
source "${_DEPLOY_CONTEXT_DIR}/env_helpers.sh"

# shellcheck source=scripts/lib/compose_plan.sh
source "${_DEPLOY_CONTEXT_DIR}/compose_plan.sh"

# shellcheck source=scripts/lib/env_file_chain.sh
source "${_DEPLOY_CONTEXT_DIR}/env_file_chain.sh"

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
  if [[ -n "$env_files_blob" ]]; then
    local env_chain_output=""
    if ! env_chain_output="$(env_file_chain__resolve_explicit "$env_files_blob" "")"; then
      return 1
    fi
    if [[ -n "$env_chain_output" ]]; then
      mapfile -t env_files_rel <<<"$env_chain_output"
    fi
  fi

  if ((${#env_files_rel[@]} == 0)); then
    local defaults_output=""
    if ! defaults_output="$(env_file_chain__defaults "$repo_root" "$instance")"; then
      return 1
    fi
    if [[ -n "$defaults_output" ]]; then
      mapfile -t env_files_rel <<<"$defaults_output"
    fi
  fi

  if ((${#env_files_rel[@]} == 0)); then
    env_files_rel=("$local_env_file")
  fi

  declare -a env_files_abs=()
  mapfile -t env_files_abs < <(
    env_file_chain__to_absolute "$repo_root" "${env_files_rel[@]}"
  )

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

  local app_data_dir_was_set=0
  local previous_app_data_dir=""
  if [[ -v APP_DATA_DIR ]]; then
    app_data_dir_was_set=1
    previous_app_data_dir="$APP_DATA_DIR"
  fi

  local app_data_dir_mount_was_set=0
  local previous_app_data_dir_mount=""
  if [[ -v APP_DATA_DIR_MOUNT ]]; then
    app_data_dir_mount_was_set=1
    previous_app_data_dir_mount="$APP_DATA_DIR_MOUNT"
  fi

  local -A loaded_env_values=()
  local -a requested_env_keys=(
    APP_DATA_DIR
    APP_DATA_DIR_MOUNT
    COMPOSE_EXTRA_FILES
    APP_DATA_UID
    APP_DATA_GID
  )

  local env_file_abs
  for env_file_abs in "${env_files_abs[@]}"; do
    local env_output=""
    if env_output="$("${_DEPLOY_CONTEXT_DIR}/env_loader.sh" "$env_file_abs" "${requested_env_keys[@]}" 2>/dev/null)"; then
      local line key value
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != *=* ]]; then
          continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        loaded_env_values[$key]="$value"
      done <<<"$env_output"
    fi
  done

  local key
  for key in "${requested_env_keys[@]}"; do
    if [[ -n "${loaded_env_values[$key]+x}" ]]; then
      if [[ "$key" == "COMPOSE_EXTRA_FILES" && -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
        continue
      fi
      export "$key=${loaded_env_values[$key]}"
    fi
  done

  local primary_app="$instance"
  local app_names_string=""
  local default_app_data_dir=""
  if [[ -n "$primary_app" && -n "$instance" ]]; then
    default_app_data_dir="data/${instance}/${primary_app}"
  fi

  local service_slug="$primary_app"

  local app_data_dir_value_raw="${APP_DATA_DIR:-}"
  local app_data_dir_mount_value_raw="${APP_DATA_DIR_MOUNT:-}"

  local derived_app_data_dir=""
  local derived_app_data_dir_mount=""
  if ! env_helpers__derive_app_data_paths "$repo_root" "$service_slug" "$default_app_data_dir" "$app_data_dir_value_raw" "$app_data_dir_mount_value_raw" derived_app_data_dir derived_app_data_dir_mount; then
    return 1
  fi

  if ((app_data_dir_was_set == 1)); then
    APP_DATA_DIR="$previous_app_data_dir"
  else
    unset APP_DATA_DIR
  fi

  if ((app_data_dir_mount_was_set == 1)); then
    APP_DATA_DIR_MOUNT="$previous_app_data_dir_mount"
  else
    unset APP_DATA_DIR_MOUNT
  fi

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

  local compose_files_string="${compose_files_list[*]}"

  local env_files_string=""
  if [[ ${#env_files_rel[@]} -gt 0 ]]; then
    env_files_string="$(printf '%s\n' "${env_files_rel[@]}")"
    env_files_string="${env_files_string%$'\n'}"
  fi

  local -a persistent_dirs=("$derived_app_data_dir_mount" "$repo_root/backups")
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
  printf '  [APP_DATA_DIR]=%q\n' "$derived_app_data_dir"
  printf '  [APP_DATA_DIR_MOUNT]=%q\n' "$derived_app_data_dir_mount"
  printf '  [PERSISTENT_DIRS]=%q\n' "$persistent_dirs_string"
  printf '  [DATA_UID]=%q\n' "$data_uid"
  printf '  [DATA_GID]=%q\n' "$data_gid"
  printf '  [APP_DATA_UID_GID]=%q\n' "$app_data_uid_gid"
  printf '  [APP_NAMES]=%q\n' "$app_names_string"
  printf ')\n'
}
