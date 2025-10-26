#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

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

  local env_file_rel="${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}"
  local env_file=""

  if [[ -n "$env_file_rel" ]]; then
    env_file="$repo_root/$env_file_rel"
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
  elif [[ -n "$env_file_rel" && -f "$env_file" ]]; then
    local extra_output
    if extra_output="$("$env_loader" "$env_file" COMPOSE_EXTRA_FILES)" && [[ -n "$extra_output" ]]; then
      extra_files_source="${extra_output#COMPOSE_EXTRA_FILES=}"
    fi
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

  if ((missing == 1)); then
    return 1
  fi

  env_args_ref=()
  if [[ -n "$env_file_rel" && -f "$env_file" ]]; then
    env_args_ref=("--env-file" "$env_file")
  fi

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
