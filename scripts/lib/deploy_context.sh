#!/usr/bin/env bash

_DEPLOY_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./env_helpers.sh
# shellcheck disable=SC1091
source "${_DEPLOY_CONTEXT_DIR}/env_helpers.sh"

# shellcheck source=./compose_instances.sh
# shellcheck disable=SC1091
source "${_DEPLOY_CONTEXT_DIR}/compose_instances.sh"

append_unique_file() {
  local -n __target_array="$1"
  local __file="$2"
  local existing

  if [[ -z "$__file" ]]; then
    return
  fi

  for existing in "${__target_array[@]}"; do
    if [[ "$existing" == "$__file" ]]; then
      return
    fi
  done

  __target_array+=("$__file")
}

load_deploy_metadata() {
  local repo_root="$1"

  if [[ -n "${DEPLOY_METADATA_LOADED:-}" ]]; then
    return 0
  fi

  if ! load_compose_instances "$repo_root"; then
    echo "[!] Não foi possível carregar metadados das instâncias." >&2
    return 1
  fi

  DEPLOY_METADATA_LOADED=1
  return 0
}

build_deploy_context() {
  local repo_root="$1"
  local instance="$2"

  if ! load_deploy_metadata "$repo_root"; then
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
    mapfile -t candidate_files < <(
      find "$repo_root/compose/apps" -mindepth 2 -maxdepth 2 -name "${instance}.yml" -print 2>/dev/null
    )

    if [[ ${#candidate_files[@]} -gt 0 ]]; then
      echo "[!] Metadados ausentes para instância '$instance'." >&2
    else
      echo "[!] Instância '$instance' inválida." >&2
    fi
    echo "    Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
    return 1
  fi

  if [[ -z "${COMPOSE_INSTANCE_FILES[$instance]-}" ]]; then
    mapfile -t candidate_files < <(
      find "$repo_root/compose/apps" -mindepth 2 -maxdepth 2 -name "${instance}.yml" -print 2>/dev/null
    )

    if [[ ${#candidate_files[@]} -gt 0 ]]; then
      echo "[!] Metadados ausentes para instância '$instance'." >&2
    else
      echo "[!] Instância '$instance' inválida." >&2
    fi
    echo "    Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
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
      echo "[!] Arquivo env/local/${instance}.env não encontrado." >&2
      echo "    Copie o template padrão antes de continuar:" >&2
      echo "    mkdir -p env/local" >&2
      echo "    cp ${template_file} env/local/${instance}.env" >&2
    else
      echo "[!] Nenhum arquivo .env foi encontrado para a instância '$instance'." >&2
      echo "    Esperado: env/local/${instance}.env ou ${template_display}" >&2
    fi
    return 1
  fi

  local env_file="$local_env_file"
  local env_file_abs="$repo_root/$env_file"

  if [[ ! -f "$env_file_abs" ]]; then
    echo "[!] Arquivo ${env_file} não encontrado." >&2
    if [[ -n "$template_file" && -f "$repo_root/$template_file" ]]; then
      echo "    Copie o template padrão antes de continuar:" >&2
      echo "    cp ${template_file} ${env_file}" >&2
    elif [[ -n "$template_file" ]]; then
      echo "    Template correspondente (${template_file}) também não foi localizado." >&2
    fi
    return 1
  fi

  if [[ -n "$env_file_abs" ]]; then
    load_env_pairs "$env_file_abs" \
      COMPOSE_EXTRA_FILES \
      APP_DATA_UID \
      APP_DATA_GID
  fi

  local app_name=""
  if [[ -v COMPOSE_INSTANCE_APP_NAMES["$instance"] ]]; then
    app_name="${COMPOSE_INSTANCE_APP_NAMES[$instance]}"
  fi
  if [[ -z "$app_name" ]]; then
    echo "[!] Aplicação correspondente à instância '$instance' não encontrada." >&2
    return 1
  fi

  local app_data_dir="data/${app_name}-${instance}"
  local -a extra_compose_files=()
  if [[ -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
    IFS=$' \t\n' read -r -a extra_compose_files <<<"${COMPOSE_EXTRA_FILES//,/ }"
  fi

  local -a instance_compose_files=()
  local instance_compose_blob="${COMPOSE_INSTANCE_FILES[$instance]}"
  mapfile -t instance_compose_files < <(printf '%s\n' "$instance_compose_blob")
  local -a compose_files_list=()

  append_unique_file compose_files_list "$BASE_COMPOSE_FILE"
  append_unique_file compose_files_list "compose/apps/${app_name}/base.yml"

  local compose_file
  for compose_file in "${instance_compose_files[@]}"; do
    append_unique_file compose_files_list "$compose_file"
  done

  if [[ ${#extra_compose_files[@]} -gt 0 ]]; then
    compose_files_list+=("${extra_compose_files[@]}")
  fi

  local compose_files_string="${compose_files_list[*]}"

  local -a persistent_dirs=("$repo_root/$app_data_dir" "$repo_root/backups")
  local persistent_dirs_string
  persistent_dirs_string="$(printf '%s\n' "${persistent_dirs[@]}")"

  local data_uid="${APP_DATA_UID:-1000}"
  local data_gid="${APP_DATA_GID:-1000}"
  local app_data_uid_gid="${data_uid}:${data_gid}"

  printf 'declare -A DEPLOY_CONTEXT=(\n'
  printf '  [INSTANCE]=%q\n' "$instance"
  printf '  [COMPOSE_ENV_FILE]=%q\n' "$env_file"
  printf '  [COMPOSE_FILES]=%q\n' "$compose_files_string"
  printf '  [APP_DATA_DIR]=%q\n' "$app_data_dir"
  printf '  [PERSISTENT_DIRS]=%q\n' "$persistent_dirs_string"
  printf '  [DATA_UID]=%q\n' "$data_uid"
  printf '  [DATA_GID]=%q\n' "$data_gid"
  printf '  [APP_DATA_UID_GID]=%q\n' "$app_data_uid_gid"
  printf ')\n'
}
