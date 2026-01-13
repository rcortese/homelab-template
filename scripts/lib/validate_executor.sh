#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

VALIDATE_EXECUTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/env_file_chain.sh
source "$VALIDATE_EXECUTOR_DIR/env_file_chain.sh"

# shellcheck source=scripts/lib/compose_plan.sh
source "$VALIDATE_EXECUTOR_DIR/compose_plan.sh"

# shellcheck source=scripts/lib/compose_file_utils.sh
source "$VALIDATE_EXECUTOR_DIR/compose_file_utils.sh"

# shellcheck source=scripts/lib/consolidated_compose.sh
source "$VALIDATE_EXECUTOR_DIR/consolidated_compose.sh"
# shellcheck source=scripts/lib/compose_yaml_validation.sh
source "$VALIDATE_EXECUTOR_DIR/compose_yaml_validation.sh"

validate_executor_print_root_cause() {
  if [[ $# -lt 2 ]]; then
    echo "validate_executor_print_root_cause: expected <compose_output> <files_ref>" >&2
    return 64
  fi

  local compose_output="$1"
  local files_name="$2"
  local -n __files_ref=$files_name

  local root_cause=""
  local compose_line
  while IFS= read -r compose_line; do
    [[ -z "$compose_line" ]] && continue
    root_cause="$compose_line"
    break
  done <<<"$compose_output"

  if [[ -n "$root_cause" ]]; then
    echo "   Root cause (from docker compose): $root_cause" >&2
  fi

  if ((${#__files_ref[@]} > 0)); then
    echo "   compose plan order:" >&2
    local idx
    for idx in "${!__files_ref[@]}"; do
      echo "     $((idx + 1)). ${__files_ref[$idx]}" >&2
    done
  fi
}

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
    local -a potential_matches=()
    local -a compose_aliases=(
      "$repo_root/compose/docker-compose.${instance}.yml"
      "$repo_root/compose/docker-compose.${instance}.yaml"
      "$repo_root/compose/${instance}.yml"
      "$repo_root/compose/${instance}.yaml"
    )

    local compose_candidate
    for compose_candidate in "${compose_aliases[@]}"; do
      if [[ -f "$compose_candidate" ]]; then
        potential_matches+=("${compose_candidate#"$repo_root"/}")
      fi
    done

    if [[ ${#potential_matches[@]} -gt 0 ]]; then
      echo "[x] instance=\"$instance\" (compose metadata missing for: ${potential_matches[*]})" >&2
      return 1
    fi

    local local_candidate="$repo_root/env/local/${instance}.env"
    local template_candidate="$repo_root/env/${instance}.example.env"
    if [[ -f "$local_candidate" || -f "$template_candidate" ]]; then
      echo "[x] instance=\"$instance\" (missing compose file: compose/docker-compose.${instance}.yml or supported alias)" >&2
      return 1
    fi

    echo "Error: unknown instance '$instance'." >&2
    return 2
  fi

  local env_files_blob="${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}"
  local -a env_files_rel=()
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

  declare -A env_loaded=()
  if [[ ${#env_files_abs[@]} -gt 0 ]]; then
    local env_file_path env_output line
    for env_file_path in "${env_files_abs[@]}"; do
      if [[ -f "$env_file_path" ]]; then
        if env_output="$("$env_loader" "$env_file_path" REPO_ROOT LOCAL_INSTANCE APP_DATA_DIR APP_DATA_DIR_MOUNT 2>/dev/null)"; then
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

  if [[ -n "${env_loaded[REPO_ROOT]:-}" ]]; then
    echo "[x] instance=\"$instance\" (REPO_ROOT must not be set in env files)" >&2
    return 1
  fi

  if [[ -n "${env_loaded[LOCAL_INSTANCE]:-}" ]]; then
    echo "[x] instance=\"$instance\" (LOCAL_INSTANCE must not be set in env files)" >&2
    return 1
  fi

  if [[ -n "${env_loaded[APP_DATA_DIR]:-}" || -n "${env_loaded[APP_DATA_DIR_MOUNT]:-}" ]]; then
    echo "[x] instance=\"$instance\" (APP_DATA_DIR and APP_DATA_DIR_MOUNT are no longer supported)" >&2
    return 1
  fi

  derived_env_ref[LOCAL_INSTANCE]="$instance"
  derived_env_ref[REPO_ROOT]="$repo_root"

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

    if ! compose_yaml_validate_services_mapping "$repo_root" "${files[@]}"; then
      echo "[x] instance=\"$instance\" (compose YAML validation failed)" >&2
      status=1
      continue
    fi

    echo "==> Validating $instance"
    local local_instance_env="${derived_env[LOCAL_INSTANCE]:-}"

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
        LOCAL_INSTANCE="$local_instance_env" \
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
          echo "   failing files: ${files[*]}" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: LOCAL_INSTANCE=\"$local_instance_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            validate_executor_print_root_cause "$compose_output" files
          fi
          status=1
        fi
      else
        compose_output="$(LOCAL_INSTANCE="$local_instance_env" \
          "${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}" config 2>&1)"
        compose_status=$?

        if ((compose_status == 0)); then
          echo "[+] $instance"
        else
          echo "[x] instance=\"$instance\" (docker compose config exited with status $compose_status)" >&2
          echo "   failing files: ${files[*]}" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: LOCAL_INSTANCE=\"$local_instance_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            validate_executor_print_root_cause "$compose_output" files
          fi
          status=1
        fi
      fi
    else
      local -a consolidated_plan=("${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}")
      if ((${#consolidated_plan[@]} == 0)); then
        echo "[x] instance=\"$instance\" (compose command is empty; cannot prepare consolidated plan)" >&2
        status=1
        continue
      fi
      local consolidated_file="$repo_root/docker-compose.yml"

      if compose_output_file=$(mktemp -t validate-compose-consolidated.XXXXXX 2>/dev/null); then
        if compose_generate_consolidated "$repo_root" consolidated_plan "$consolidated_file" derived_env \
          2>"$compose_output_file"; then
          rm -f "$compose_output_file"
        else
          compose_status=$?
        fi
      else
        compose_output="$(compose_generate_consolidated "$repo_root" consolidated_plan "$consolidated_file" derived_env 2>&1)"
        compose_status=$?
      fi

      if ((compose_status != 0)); then
        echo "[x] instance=\"$instance\" (failed to generate consolidated docker-compose.yml)" >&2
        echo "   failing files: ${files[*]}" >&2
        if ((${#env_files_pretty[@]} > 0)); then
          echo "   env files: ${env_files_pretty[*]}" >&2
        else
          echo "   env files: (none)" >&2
        fi
        echo "   derived env: LOCAL_INSTANCE=\"$local_instance_env\"" >&2
        status=1
        if [[ -n "$compose_output_file" && -f "$compose_output_file" ]]; then
          compose_output=$(<"$compose_output_file")
          rm -f "$compose_output_file"
        fi
        if [[ -n "$compose_output" ]]; then
          while IFS= read -r compose_line; do
            [[ -z "$compose_line" ]] && continue
            if [[ "$compose_line" == " "* ]]; then
              echo "$compose_line" >&2
            else
              echo "   $compose_line" >&2
            fi
          done <<<"$compose_output"
        else
          echo "   compose plan order:" >&2
          local idx
          for idx in "${!files[@]}"; do
            echo "     $((idx + 1)). ${files[$idx]}" >&2
          done
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
        LOCAL_INSTANCE="$local_instance_env" \
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
          echo "   failing files: ${files[*]}" >&2
          echo "   consolidated file: $consolidated_file" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: LOCAL_INSTANCE=\"$local_instance_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            validate_executor_print_root_cause "$compose_output" files
          fi
          status=1
        fi
      else
        compose_output="$(LOCAL_INSTANCE="$local_instance_env" \
          "${consolidated_cmd[@]}" config -q 2>&1)"
        compose_status=$?
        if ((compose_status == 0)); then
          echo "[+] $instance"
        else
          echo "[x] instance=\"$instance\" (docker compose config -q exited with status $compose_status)" >&2
          echo "   failing files: ${files[*]}" >&2
          echo "   consolidated file: $consolidated_file" >&2
          if ((${#env_files_pretty[@]} > 0)); then
            echo "   env files: ${env_files_pretty[*]}" >&2
          else
            echo "   env files: (none)" >&2
          fi
          echo "   derived env: LOCAL_INSTANCE=\"$local_instance_env\"" >&2
          if [[ -n "$compose_output" ]]; then
            validate_executor_print_root_cause "$compose_output" files
          fi
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
