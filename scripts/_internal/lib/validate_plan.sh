#!/usr/bin/env bash

# Helpers to assemble compose plan/env details for validation.

VALIDATE_PLAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/_internal/lib/env_file_chain.sh
source "$VALIDATE_PLAN_DIR/env_file_chain.sh"

# shellcheck source=scripts/_internal/lib/compose_plan.sh
source "$VALIDATE_PLAN_DIR/compose_plan.sh"

# shellcheck source=scripts/_internal/lib/compose_file_utils.sh
source "$VALIDATE_PLAN_DIR/compose_file_utils.sh"

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
