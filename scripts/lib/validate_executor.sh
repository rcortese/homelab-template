#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

VALIDATE_EXECUTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/env_file_chain.sh
source "$VALIDATE_EXECUTOR_DIR/env_file_chain.sh"

# shellcheck source=scripts/lib/env_helpers.sh
source "$VALIDATE_EXECUTOR_DIR/env_helpers.sh"

# shellcheck source=scripts/lib/compose_plan.sh
source "$VALIDATE_EXECUTOR_DIR/compose_plan.sh"

# shellcheck source=scripts/lib/compose_file_utils.sh
source "$VALIDATE_EXECUTOR_DIR/compose_file_utils.sh"

# shellcheck source=scripts/lib/consolidated_compose.sh
source "$VALIDATE_EXECUTOR_DIR/consolidated_compose.sh"

validate_executor_prepare_plan() {
  local instance="$1"
  local repo_root="$2"
  local base_file="$3"
  local env_loader="$4"
  local -n files_ref=$5
  local -n compose_args_ref=$6
  local -n env_args_ref=$7
  local -n derived_env_ref=$8

  if [[ ! -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
    mapfile -t potential_matches < <(
      find "$repo_root/compose/apps" -mindepth 2 -maxdepth 2 -name "${instance}.yml" -print 2>/dev/null
    )

    if [[ ${#potential_matches[@]} -gt 0 ]]; then
      echo "[x] instance=\"$instance\" (file combination missing from metadata)" >&2
      return 1
    fi

    local local_candidate="$repo_root/env/local/${instance}.env"
    local template_candidate="$repo_root/env/${instance}.example.env"
    if [[ -f "$local_candidate" || -f "$template_candidate" ]]; then
      echo "[x] instance=\"$instance\" (missing file: compose/apps/*/${instance}.yml)" >&2
      return 1
    fi

    echo "Error: unknown instance '$instance'." >&2
    return 2
  fi

  local env_files_blob="${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}"
  local -a env_files_rel=()
  if [[ -n "$env_files_blob" ]]; then
    mapfile -t env_files_rel < <(
      env_file_chain__resolve_explicit "$env_files_blob" ""
    )
  fi

  if ((${#env_files_rel[@]} == 0)); then
    mapfile -t env_files_rel < <(
      env_file_chain__defaults "$repo_root" "$instance"
    )
  fi

  local -a env_files_abs=()
  if ((${#env_files_rel[@]} > 0)); then
    mapfile -t env_files_abs < <(
      env_file_chain__to_absolute "$repo_root" "${env_files_rel[@]}"
    )
  fi

  local -a extra_files=()
  local extra_files_source=""

  if [[ -n "${COMPOSE_EXTRA_FILES+x}" ]]; then
    extra_files_source="$COMPOSE_EXTRA_FILES"
  elif [[ ${#env_files_abs[@]} -gt 0 ]]; then
    local extra_output env_file_path
    for env_file_path in "${env_files_abs[@]}"; do
      if [[ -f "$env_file_path" ]]; then
        if extra_output="$("$env_loader" "$env_file_path" COMPOSE_EXTRA_FILES)" && [[ -n "$extra_output" ]]; then
          extra_files_source="${extra_output#COMPOSE_EXTRA_FILES=}"
        fi
      fi
    done
  fi

  if [[ -n "$extra_files_source" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      extra_files+=("$entry")
    done < <(parse_compose_file_list "$extra_files_source")
  fi

  local -a compose_plan_rel=()
  if ! build_compose_file_plan "$instance" compose_plan_rel extra_files; then
    echo "[x] instance=\"$instance\" (failed to build compose file plan)" >&2
    return 1
  fi

  local -a instance_app_names=()
  if [[ -n "${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}" ]]; then
    mapfile -t instance_app_names < <(printf '%s\n' "${COMPOSE_INSTANCE_APP_NAMES[$instance]}")
  fi

  files_ref=()
  local plan_entry resolved_entry
  for plan_entry in "${compose_plan_rel[@]}"; do
    [[ -z "$plan_entry" ]] && continue
    if [[ "$plan_entry" == /* ]]; then
      resolved_entry="$plan_entry"
    else
      resolved_entry="$repo_root/${plan_entry#./}"
    fi
    files_ref+=("$resolved_entry")
  done

  if [[ -n "$base_file" ]]; then
    local base_expected="$base_file"
    if [[ "$base_expected" != /* ]]; then
      base_expected="$repo_root/${base_expected#./}"
    fi
    if [[ ${#files_ref[@]} -eq 0 || "${files_ref[0]}" != "$base_expected" ]]; then
      files_ref=("$base_expected" "${files_ref[@]}")
    fi
  fi

  compose_args_ref=()
  local missing=0
  local file
  for file in "${files_ref[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "[x] instance=\"$instance\" (missing file: $file)" >&2
      missing=1
    else
      compose_args_ref+=("-f" "$file")
    fi
  done

  local env_missing=0
  env_args_ref=()
  if [[ ${#env_files_abs[@]} -gt 0 ]]; then
    local env_path
    for env_path in "${env_files_abs[@]}"; do
      if [[ -f "$env_path" ]]; then
        env_args_ref+=("--env-file" "$env_path")
      else
        echo "[x] instance=\"$instance\" (missing file: $env_path)" >&2
        env_missing=1
      fi
    done
  fi

  if ((missing == 1 || env_missing == 1)); then
    return 1
  fi

  derived_env_ref=()

  local -a instance_app_names=()
  if [[ -v COMPOSE_INSTANCE_APP_NAMES[$instance] ]]; then
    mapfile -t instance_app_names < <(printf '%s\n' "${COMPOSE_INSTANCE_APP_NAMES[$instance]}")
  fi
  if [[ ${#instance_app_names[@]} -gt 0 ]]; then
    local -a filtered_app_names=()
    local instance_app_name
    for instance_app_name in "${instance_app_names[@]}"; do
      if [[ -n "${COMPOSE_APP_BASE_FILES[$instance_app_name]:-}" ]]; then
        filtered_app_names+=("$instance_app_name")
      fi
    done
    if [[ ${#filtered_app_names[@]} -gt 0 ]]; then
      instance_app_names=("${filtered_app_names[@]}")
    fi
  fi
  if [[ ${#instance_app_names[@]} -eq 0 ]]; then
    echo "[x] instance=\"$instance\" (associated applications not found)" >&2
    return 1
  fi

  local primary_app=""
  if [[ ${#instance_app_names[@]} -gt 0 ]]; then
    primary_app="${instance_app_names[0]}"
  fi

  declare -A env_loaded=()
  if [[ ${#env_files_abs[@]} -gt 0 ]]; then
    local env_file_path env_output line
    for env_file_path in "${env_files_abs[@]}"; do
      if [[ -f "$env_file_path" ]]; then
        if env_output="$("$env_loader" "$env_file_path" APP_DATA_DIR APP_DATA_DIR_MOUNT 2>/dev/null)"; then
          while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$line" == *=* ]]; then
              local key="${line%%=*}"
              local value="${line#*=}"
              env_loaded[$key]="$value"
            fi
          done <<<"$env_output"
        fi
      fi
    done
  fi

  local app_data_dir_value="${APP_DATA_DIR:-}"
  local app_data_dir_mount_value="${APP_DATA_DIR_MOUNT:-}"

  if [[ -z "$app_data_dir_value" && -n "${env_loaded[APP_DATA_DIR]:-}" ]]; then
    app_data_dir_value="${env_loaded[APP_DATA_DIR]}"
  fi
  if [[ -z "$app_data_dir_mount_value" && -n "${env_loaded[APP_DATA_DIR_MOUNT]:-}" ]]; then
    app_data_dir_mount_value="${env_loaded[APP_DATA_DIR_MOUNT]}"
  fi

  local default_app_data_dir=""
  local service_slug=""
  if [[ -n "$primary_app" ]]; then
    service_slug="$primary_app"
    if [[ -n "$instance" ]]; then
      default_app_data_dir="data/${instance}/${primary_app}"
    fi
  fi

  local derived_app_data_dir=""
  local derived_app_data_dir_mount=""
  local precomputed_values=0

  if [[ -n "$service_slug" && -n "$app_data_dir_value" && -n "$app_data_dir_mount_value" ]]; then
    local temp_app_data_dir=""
    local temp_app_data_mount=""

    if env_helpers__derive_app_data_paths \
      "$repo_root" \
      "$service_slug" \
      "$default_app_data_dir" \
      "$app_data_dir_value" \
      "" \
      temp_app_data_dir \
      temp_app_data_mount; then
      if [[ -n "$temp_app_data_mount" && "$temp_app_data_mount" == "$app_data_dir_mount_value" ]]; then
        derived_app_data_dir="$temp_app_data_dir"
        derived_app_data_dir_mount="$app_data_dir_mount_value"
        precomputed_values=1
      fi
    fi

    if ((precomputed_values == 0)); then
      temp_app_data_dir=""
      temp_app_data_mount=""
      if env_helpers__derive_app_data_paths \
        "$repo_root" \
        "$service_slug" \
        "$default_app_data_dir" \
        "" \
        "$app_data_dir_mount_value" \
        temp_app_data_dir \
        temp_app_data_mount; then
        if [[ -n "$temp_app_data_mount" && "$temp_app_data_mount" == "$app_data_dir_mount_value" ]]; then
          if [[ -z "$temp_app_data_dir" ]]; then
            temp_app_data_dir="$app_data_dir_value"
          fi
          derived_app_data_dir="$temp_app_data_dir"
          derived_app_data_dir_mount="$temp_app_data_mount"
          precomputed_values=1
        fi
      fi
    fi

    if ((precomputed_values == 0)); then
      echo "[x] instance=\"$instance\" (APP_DATA_DIR and APP_DATA_DIR_MOUNT cannot be set simultaneously)" >&2
      return 1
    fi

    app_data_dir_value="$derived_app_data_dir"
    app_data_dir_mount_value="$derived_app_data_dir_mount"
  fi

  local should_derive=0
  if [[ -n "$default_app_data_dir" || -n "$app_data_dir_value" || -n "$app_data_dir_mount_value" ]]; then
    should_derive=1
  fi

  if ((precomputed_values == 1)); then
    should_derive=0
  fi

  if ((precomputed_values == 1)); then
    :
  elif ((should_derive == 1)); then
    if ! env_helpers__derive_app_data_paths \
      "$repo_root" \
      "$service_slug" \
      "$default_app_data_dir" \
      "$app_data_dir_value" \
      "$app_data_dir_mount_value" \
      derived_app_data_dir \
      derived_app_data_dir_mount; then
      echo "[x] instance=\"$instance\" (failed to derive persistent directories)" >&2
      return 1
    fi
  else
    derived_app_data_dir="$app_data_dir_value"
    derived_app_data_dir_mount="$app_data_dir_mount_value"
  fi

  derived_env_ref[APP_DATA_DIR]="$derived_app_data_dir"
  derived_env_ref[APP_DATA_DIR_MOUNT]="$derived_app_data_dir_mount"

  # Touch nameref arrays so shellcheck recognizes they are consumed by callers.
  : "${env_args_ref[@]}"
  : "${derived_env_ref[@]}"

  return 0
}

validate_executor_run_instances() {
  local had_errexit=0
  if [[ $- == *e* ]]; then
    had_errexit=1
    set +e
  fi

  local repo_root="$1"
  local base_file="$2"
  local env_loader="$3"
  local instances_array_name="$4"
  shift 4
  local -n instances_ref=$instances_array_name
  local -a compose_cmd=("$@")

  local status=0
  declare -A seen=()
  local instance

  for instance in "${instances_ref[@]}"; do
    [[ -z "$instance" ]] && continue
    if [[ -n "${seen[$instance]:-}" ]]; then
      continue
    fi
    seen[$instance]=1

    local -a files=()
    local -a compose_args=()
    local -a env_args=()
    declare -A derived_env=()
    if ! validate_executor_prepare_plan "$instance" "$repo_root" "$base_file" "$env_loader" files compose_args env_args derived_env; then
      local prepare_status=$?
      if [[ $prepare_status -eq 2 ]]; then
        return 2
      fi
      status=1
      continue
    fi

    echo "==> Validating $instance"
    local app_data_dir_env="${derived_env[APP_DATA_DIR]:-}"
    local app_data_dir_mount_env="${derived_env[APP_DATA_DIR_MOUNT]:-}"

    local -a env_files_pretty=()
    if ((${#env_args[@]} > 0)); then
      local idx=0
      while ((idx < ${#env_args[@]})); do
        local token="${env_args[idx]}"
        if [[ "$token" == "--env-file" ]]; then
          ((idx++))
          if ((idx < ${#env_args[@]})); then
            env_files_pretty+=("${env_args[idx]}")
          fi
        fi
        ((idx++))
      done
    fi

    local compose_output=""
    local compose_status=0
    local compose_output_file=""

    if [[ "${VALIDATE_USE_LEGACY_PLAN:-false}" == "true" ]]; then
      if compose_output_file=$(mktemp -t validate-compose-config.XXXXXX 2>/dev/null); then
        APP_DATA_DIR="$app_data_dir_env" \
          APP_DATA_DIR_MOUNT="$app_data_dir_mount_env" \
          "${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}" config \
          >"$compose_output_file" 2>&1
        compose_status=$?

        if ((compose_status == 0)); then
          rm -f "$compose_output_file"
          echo "[+] $instance"
        else
          compose_output=$(<"$compose_output_file")
          rm -f "$compose_output_file"
          echo "[x] instance=\"$instance\" (docker compose config exited with status $compose_status)" >&2
          echo "   files: ${files[*]}" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: APP_DATA_DIR=\"$app_data_dir_env\" APP_DATA_DIR_MOUNT=\"$app_data_dir_mount_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            echo "   docker compose config output:" >&2
            while IFS= read -r compose_line; do
              echo "     $compose_line" >&2
            done <<<"$compose_output"
          fi
          status=1
        fi
      else
        APP_DATA_DIR="$app_data_dir_env" \
          APP_DATA_DIR_MOUNT="$app_data_dir_mount_env" \
          "${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}" config >/dev/null 2>&1
        compose_status=$?

        if ((compose_status == 0)); then
          echo "[+] $instance"
        else
          echo "[x] instance=\"$instance\" (docker compose config exited with status $compose_status)" >&2
          echo "   files: ${files[*]}" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: APP_DATA_DIR=\"$app_data_dir_env\" APP_DATA_DIR_MOUNT=\"$app_data_dir_mount_env\"" >&2
          status=1
        fi
      fi
    else
      local -a consolidated_plan=("${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}")
      local consolidated_file="$repo_root/docker-compose.yml"

      if compose_output_file=$(mktemp -t validate-compose-consolidated.XXXXXX 2>/dev/null); then
        if ! compose_generate_consolidated "$repo_root" consolidated_plan "$consolidated_file" derived_env \
          2>"$compose_output_file"; then
          compose_status=$?
        else
          rm -f "$compose_output_file"
        fi
      else
        compose_generate_consolidated "$repo_root" consolidated_plan "$consolidated_file" derived_env >/dev/null 2>&1
        compose_status=$?
      fi

      if ((compose_status != 0)); then
        echo "[x] instance=\"$instance\" (failed to generate consolidated docker-compose.yml)" >&2
        echo "   files: ${files[*]}" >&2
        if ((${#env_files_pretty[@]} > 0)); then
          echo "   env files: ${env_files_pretty[*]}" >&2
        else
          echo "   env files: (none)" >&2
        fi
        echo "   derived env: APP_DATA_DIR=\"$app_data_dir_env\" APP_DATA_DIR_MOUNT=\"$app_data_dir_mount_env\"" >&2
        status=1
        if [[ -n "$compose_output_file" && -f "$compose_output_file" ]]; then
          compose_output=$(<"$compose_output_file")
          rm -f "$compose_output_file"
          if [[ -n "$compose_output" ]]; then
            echo "   docker compose config output:" >&2
            while IFS= read -r compose_line; do
              echo "     $compose_line" >&2
            done <<<"$compose_output"
          fi
        fi
        continue
      fi

      if [[ -n "$compose_output_file" && -f "$compose_output_file" ]]; then
        rm -f "$compose_output_file"
      fi

      local -a consolidated_cmd=("${compose_cmd[@]}" "${env_args[@]}")
      compose_strip_file_flags consolidated_cmd consolidated_cmd
      consolidated_cmd+=(-f "$consolidated_file")

      if compose_output_file=$(mktemp -t validate-compose-config.XXXXXX 2>/dev/null); then
        APP_DATA_DIR="$app_data_dir_env" \
          APP_DATA_DIR_MOUNT="$app_data_dir_mount_env" \
          "${consolidated_cmd[@]}" config -q \
          >"$compose_output_file" 2>&1
        compose_status=$?
        if ((compose_status == 0)); then
          rm -f "$compose_output_file"
          echo "[+] $instance"
        else
          compose_output=$(<"$compose_output_file")
          rm -f "$compose_output_file"
          echo "[x] instance=\"$instance\" (docker compose config -q exited with status $compose_status)" >&2
          echo "   files: ${files[*]}" >&2
          echo "   consolidated file: $consolidated_file" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: APP_DATA_DIR=\"$app_data_dir_env\" APP_DATA_DIR_MOUNT=\"$app_data_dir_mount_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            echo "   docker compose config output:" >&2
            while IFS= read -r compose_line; do
              echo "     $compose_line" >&2
            done <<<"$compose_output"
          fi
          status=1
        fi
      else
        APP_DATA_DIR="$app_data_dir_env" \
          APP_DATA_DIR_MOUNT="$app_data_dir_mount_env" \
          "${consolidated_cmd[@]}" config -q >/dev/null 2>&1
        compose_status=$?
        if ((compose_status == 0)); then
          echo "[+] $instance"
        else
          echo "[x] instance=\"$instance\" (docker compose config -q exited with status $compose_status)" >&2
          echo "   files: ${files[*]}" >&2
          echo "   consolidated file: $consolidated_file" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: APP_DATA_DIR=\"$app_data_dir_env\" APP_DATA_DIR_MOUNT=\"$app_data_dir_mount_env\"" >&2
          status=1
        fi
      fi
    fi
  done

  if ((had_errexit == 1)); then
    set -e
  fi
  return $status
}
