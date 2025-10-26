#!/usr/bin/env bash
set -euo pipefail

print_help() {
  cat <<'USAGE'
Uso: scripts/compose.sh [instancia] [--] [argumentos...]

Wrapper para montar comandos docker compose reutilizando convenções do repositório.

Argumentos posicionais:
  instancia        Nome da instância (ex.: core). Quando informado, carrega compose/base.yml
                   + manifests da aplicação (ex.: compose/apps/app/base.yml e
                   compose/apps/app/<instancia>.yml) e busca env/local/<instancia>.env.

Flags:
  -h, --help       Exibe esta ajuda e sai.
  --               Separa os parâmetros do docker compose, útil quando o subcomando
                   começa com hífen.

Variáveis de ambiente relevantes:
  DOCKER_COMPOSE_BIN  Sobrescreve o comando docker compose (ex.: docker-compose).
  COMPOSE_FILES        Sobrescreve a lista de manifests (-f) aplicados.
  COMPOSE_ENV_FILE     Define o arquivo .env utilizado pelo docker compose.

Exemplos:
  scripts/compose.sh core up -d
  scripts/compose.sh media logs app
  scripts/compose.sh core -- down app
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INSTANCE_NAME=""
COMPOSE_ARGS=()

if [[ $# -eq 0 ]]; then
  print_help
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      COMPOSE_ARGS+=("$1")
      shift
    done
    break
    ;;
  -*)
    COMPOSE_ARGS+=("$1")
    shift
    ;;
  *)
    if [[ -z "$INSTANCE_NAME" ]]; then
      INSTANCE_NAME="$1"
    else
      COMPOSE_ARGS+=("$1")
    fi
    shift
    ;;
  esac
done

COMPOSE_FILES_LIST=()
metadata_loaded=0
declare -a resolved_instance_app_names=()

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

if [[ -n "${COMPOSE_FILES:-}" ]]; then
  # shellcheck disable=SC2206
  COMPOSE_FILES_LIST=(${COMPOSE_FILES})
elif [[ -n "$INSTANCE_NAME" ]]; then
  if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
    echo "Error: não foi possível carregar metadados das instâncias." >&2
    exit 1
  fi

  eval "$compose_metadata"
  metadata_loaded=1

  if [[ -z "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]:-}" ]]; then
    echo "Error: instância desconhecida '$INSTANCE_NAME'." >&2
    echo "Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
    exit 1
  fi

  mapfile -t instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]}")

  append_unique_file COMPOSE_FILES_LIST "$BASE_COMPOSE_FILE"

  declare -a instance_app_names=()
  apps_raw="${COMPOSE_INSTANCE_APP_NAMES[$INSTANCE_NAME]:-}"
  if [[ -n "$apps_raw" ]]; then
    mapfile -t instance_app_names < <(printf '%s\n' "$apps_raw")
    resolved_instance_app_names=("${instance_app_names[@]}")
  fi

  declare -A instance_overrides_by_app=()
  for compose_file in "${instance_compose_files[@]}"; do
    [[ -z "$compose_file" ]] && continue
    app_for_file="${compose_file#compose/apps/}"
    app_for_file="${app_for_file%%/*}"
    if [[ -z "$app_for_file" ]]; then
      continue
    fi
    if [[ -n "${instance_overrides_by_app[$app_for_file]:-}" ]]; then
      instance_overrides_by_app[$app_for_file]+=$'\n'"$compose_file"
    else
      instance_overrides_by_app[$app_for_file]="$compose_file"
    fi
  done

  for app_name in "${instance_app_names[@]}"; do
    append_unique_file COMPOSE_FILES_LIST "compose/apps/${app_name}/base.yml"
    if [[ -n "${instance_overrides_by_app[$app_name]:-}" ]]; then
      mapfile -t instance_compose_files < <(printf '%s\n' "${instance_overrides_by_app[$app_name]}")
      for override_file in "${instance_compose_files[@]}"; do
        append_unique_file COMPOSE_FILES_LIST "$override_file"
      done
    fi
  done

  mapfile -t instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]}")
  for compose_file in "${instance_compose_files[@]}"; do
    append_unique_file COMPOSE_FILES_LIST "$compose_file"
  done
fi

if [[ -z "${COMPOSE_ENV_FILE:-}" && -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 ]]; then
  if [[ -n "${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]:-}" ]]; then
    COMPOSE_ENV_FILE="${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]}"
  fi
fi

if [[ -z "${COMPOSE_ENV_FILE:-}" && -n "$INSTANCE_NAME" ]]; then
  env_candidate_rel="env/local/${INSTANCE_NAME}.env"
  if [[ -f "$REPO_ROOT/$env_candidate_rel" ]]; then
    COMPOSE_ENV_FILE="$env_candidate_rel"
  else
    env_template_rel="env/${INSTANCE_NAME}.example.env"
    if [[ -f "$REPO_ROOT/$env_template_rel" ]]; then
      COMPOSE_ENV_FILE="$env_template_rel"
    fi
  fi
fi

compose_env_file_abs=""
if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
  compose_env_file_abs="$COMPOSE_ENV_FILE"
  if [[ "$compose_env_file_abs" != /* ]]; then
    compose_env_file_abs="$REPO_ROOT/$compose_env_file_abs"
  fi
fi

app_data_dir_value="${APP_DATA_DIR:-}"

if [[ -z "$app_data_dir_value" && -n "$compose_env_file_abs" && -f "$compose_env_file_abs" ]]; then
  if app_data_dir_kv="$("$SCRIPT_DIR/lib/env_loader.sh" "$compose_env_file_abs" APP_DATA_DIR)"; then
    if [[ -n "$app_data_dir_kv" ]]; then
      app_data_dir_value="${app_data_dir_kv#APP_DATA_DIR=}"
    fi
  fi
fi

if [[ -z "$app_data_dir_value" && $metadata_loaded -eq 1 && -n "$INSTANCE_NAME" && ${#resolved_instance_app_names[@]} -gt 0 ]]; then
  primary_app_name="${resolved_instance_app_names[0]}"
  if [[ -n "$primary_app_name" ]]; then
    app_data_dir_value="data/${primary_app_name}-${INSTANCE_NAME}"
  fi
fi

if ! cd "$REPO_ROOT"; then
  echo "Error: não foi possível acessar o diretório do repositório: $REPO_ROOT" >&2
  exit 1
fi

if [[ -n "${DOCKER_COMPOSE_BIN:-}" ]]; then
  # Permite sobrescrever o binário do docker compose (ex.: "docker-compose").
  # shellcheck disable=SC2206
  COMPOSE_CMD=(${DOCKER_COMPOSE_BIN})
else
  COMPOSE_CMD=(docker compose)
fi

if ! command -v "${COMPOSE_CMD[0]}" >/dev/null 2>&1; then
  echo "Error: ${COMPOSE_CMD[0]} is not available. Set DOCKER_COMPOSE_BIN if needed." >&2
  exit 127
fi

if [[ -n "$compose_env_file_abs" ]]; then
  COMPOSE_CMD+=(--env-file "$compose_env_file_abs")
fi

if [[ ${#COMPOSE_FILES_LIST[@]} -gt 0 ]]; then
  for file in "${COMPOSE_FILES_LIST[@]}"; do
    COMPOSE_CMD+=(-f "$file")
  done
fi

if [[ ${#COMPOSE_ARGS[@]} -gt 0 ]]; then
  COMPOSE_CMD+=("${COMPOSE_ARGS[@]}")
fi

if [[ -n "$app_data_dir_value" ]]; then
  APP_DATA_DIR="$app_data_dir_value" exec -- "${COMPOSE_CMD[@]}"
else
  exec "${COMPOSE_CMD[@]}"
fi
