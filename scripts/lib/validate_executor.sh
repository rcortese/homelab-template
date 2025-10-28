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
    echo "✖ instância=\"$instance\" (falha ao gerar plano de arquivos)" >&2
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
    echo "✖ instância=\"$instance\" (aplicações associadas não encontradas)" >&2
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

  if [[ -n "$app_data_dir_value" && -n "$app_data_dir_mount_value" ]]; then
    echo "✖ instância=\"$instance\" (APP_DATA_DIR e APP_DATA_DIR_MOUNT não podem ser definidos simultaneamente)" >&2
    return 1
  fi

  local default_app_data_dir=""
  local service_slug=""
  if [[ -n "$primary_app" ]]; then
    service_slug="${primary_app}-${instance}"
    default_app_data_dir="data/${service_slug}"
  fi

  local derived_app_data_dir=""
  local derived_app_data_dir_mount=""
  if ! env_helpers__derive_app_data_paths "$repo_root" "$service_slug" "$default_app_data_dir" "$app_data_dir_value" "$app_data_dir_mount_value" derived_app_data_dir derived_app_data_dir_mount; then
    echo "✖ instância=\"$instance\" (falha ao derivar diretórios persistentes)" >&2
    return 1
  fi

  derived_env_ref[APP_DATA_DIR]="$derived_app_data_dir"
  derived_env_ref[APP_DATA_DIR_MOUNT]="$derived_app_data_dir_mount"

  # Touch nameref arrays so shellcheck recognizes they are consumed by callers.
  : "${env_args_ref[@]}"
  : "${derived_env_ref[@]}"

  return 0
}

validate_executor_run_instances() {
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

    echo "==> Validando $instance"
    local app_data_dir_env="${derived_env[APP_DATA_DIR]:-}"
    local app_data_dir_mount_env="${derived_env[APP_DATA_DIR_MOUNT]:-}"

    if APP_DATA_DIR="$app_data_dir_env" \
      APP_DATA_DIR_MOUNT="$app_data_dir_mount_env" \
      "${compose_cmd[@]}" "${env_args[@]}" "${compose_args[@]}" config >/dev/null; then
      echo "✔ $instance"
    else
      echo "✖ instância=\"$instance\"" >&2
      echo "   files: ${files[*]}" >&2
      status=1
    fi
  done

  return $status
}
