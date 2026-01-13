#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

VALIDATE_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/validate_plan.sh
source "$VALIDATE_RUNNER_DIR/validate_plan.sh"

# shellcheck source=scripts/lib/validate_output.sh
source "$VALIDATE_RUNNER_DIR/validate_output.sh"

# shellcheck source=scripts/lib/consolidated_compose.sh
source "$VALIDATE_RUNNER_DIR/consolidated_compose.sh"

# shellcheck source=scripts/lib/compose_yaml_validation.sh
source "$VALIDATE_RUNNER_DIR/compose_yaml_validation.sh"

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
