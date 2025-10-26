#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

VALIDATE_EXECUTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./env_file_chain.sh
# shellcheck disable=SC1091
source "$VALIDATE_EXECUTOR_DIR/env_file_chain.sh"

validate_executor_prepare_plan() {
  local instance="$1"
  local repo_root="$2"
  local base_file="$3"
  local env_loader="$4"
  local -n files_ref="$5"
  local -n compose_args_ref="$6"
  local -n env_args_ref="$7"

  local instance_files_raw="${COMPOSE_INSTANCE_FILES[$instance]:-}"

  if [[ -z "$instance_files_raw" ]]; then
    mapfile -t potential_matches < <(
      find "$repo_root/compose/apps" -mindepth 2 -maxdepth 2 -name "${instance}.yml" -print 2>/dev/null
    )

    if [[ ${#potential_matches[@]} -gt 0 ]]; then
      echo "✖ instância=\"$instance\" (combinação de arquivos ausente nos metadados)" >&2
      return 1
    fi

    local local_candidate="$repo_root/env/local/${instance}.env"
    local template_candidate="$repo_root/env/${instance}.example.env"
    if [[ -f "$local_candidate" || -f "$template_candidate" ]]; then
      echo "✖ instância=\"$instance\" (arquivo ausente: compose/apps/*/${instance}.yml)" >&2
      return 1
    fi

    echo "Error: instância desconhecida '$instance'." >&2
    return 2
  fi

  mapfile -t instance_file_list < <(printf '%s\n' "$instance_files_raw")

  local -a instance_app_names=()
  local instance_apps_raw="${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}"
  if [[ -n "$instance_apps_raw" ]]; then
    mapfile -t instance_app_names < <(printf '%s\n' "$instance_apps_raw")
  fi

  declare -A instance_overrides_by_app=()
  local instance_entry app_for_entry
  for instance_entry in "${instance_file_list[@]}"; do
    [[ -z "$instance_entry" ]] && continue
    app_for_entry="${instance_entry#compose/apps/}"
    app_for_entry="${app_for_entry%%/*}"
    if [[ -z "$app_for_entry" ]]; then
      continue
    fi
    if [[ -n "${instance_overrides_by_app[$app_for_entry]:-}" ]]; then
      instance_overrides_by_app[$app_for_entry]+=$'\n'"$instance_entry"
    else
      instance_overrides_by_app[$app_for_entry]="$instance_entry"
    fi
  done

  local env_files_blob="${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}"
  local -a env_files_rel=()
  env_file_chain__resolve_explicit "$env_files_blob" "" env_files_rel

  if (( ${#env_files_rel[@]} == 0 )); then
    env_file_chain__defaults "$repo_root" "$instance" env_files_rel
  fi

  local -a env_files_abs=()
  if (( ${#env_files_rel[@]} > 0 )); then
    env_file_chain__to_absolute "$repo_root" env_files_rel env_files_abs
  fi

  files_ref=("$base_file")

  local app_name
  for app_name in "${instance_app_names[@]}"; do
    files_ref+=("$(resolve_compose_file "compose/apps/${app_name}/base.yml")")
    if [[ -n "${instance_overrides_by_app[$app_name]:-}" ]]; then
      local -a app_override_entries=()
      mapfile -t app_override_entries < <(printf '%s\n' "${instance_overrides_by_app[$app_name]}")
      local override_entry
      for override_entry in "${app_override_entries[@]}"; do
        files_ref+=("$(resolve_compose_file "$override_entry")")
      done
    fi
  done

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

  local rel resolved_rel entry
  for rel in "${instance_file_list[@]}"; do
    [[ -z "$rel" ]] && continue
    resolved_rel="$(resolve_compose_file "$rel")"
    local already_in_list=0
    for entry in "${files_ref[@]}"; do
      if [[ "$entry" == "$resolved_rel" ]]; then
        already_in_list=1
        break
      fi
    done
    if ((already_in_list == 0)); then
      files_ref+=("$resolved_rel")
    fi
  done

  if [[ ${#extra_files[@]} -gt 0 ]]; then
    for rel in "${extra_files[@]}"; do
      files_ref+=("$(resolve_compose_file "$rel")")
    done
  fi

  compose_args_ref=()
  local missing=0
  local file
  for file in "${files_ref[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "✖ instância=\"$instance\" (arquivo ausente: $file)" >&2
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
        echo "✖ instância=\"$instance\" (arquivo ausente: $env_path)" >&2
        env_missing=1
      fi
    done
  fi

  if ((missing == 1 || env_missing == 1)); then
    return 1
  fi

  # Touch nameref arrays so shellcheck recognizes they are consumed by callers.
  : "${env_args_ref[@]}"

  return 0
}

validate_executor_run_instances() {
  local repo_root="$1"
  local base_file="$2"
  local env_loader="$3"
  local instances_array_name="$4"
  shift 4
  local -n instances_ref="$instances_array_name"
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
    if ! validate_executor_prepare_plan "$instance" "$repo_root" "$base_file" "$env_loader" files compose_args env_args; then
      local prepare_status=$?
      if [[ $prepare_status -eq 2 ]]; then
        return 2
      fi
      status=1
      continue
    fi

    echo "==> Validando $instance"
    if "${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}" config >/dev/null; then
      echo "✔ $instance"
    else
      echo "✖ instância=\"$instance\"" >&2
      echo "   files: ${files[*]}" >&2
      status=1
    fi
  done

  return $status
}
