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
compose_metadata=""

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

split_env_entries() {
  local raw="${1:-}"
  local -n __out="$2"

  __out=()

  if [[ -z "$raw" ]]; then
    return
  fi

  raw="${raw//$'\n'/ }"
  raw="${raw//,/ }"

  local token
  for token in $raw; do
    [[ -z "$token" ]] && continue
    __out+=("$token")
  done
}

if [[ -n "$INSTANCE_NAME" ]]; then
  if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
    if [[ -z "${COMPOSE_FILES:-}" ]]; then
      echo "Error: não foi possível carregar metadados das instâncias." >&2
      exit 1
    fi
  else
    eval "$compose_metadata"
    metadata_loaded=1

    if [[ -z "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]:-}" ]]; then
      echo "Error: instância desconhecida '$INSTANCE_NAME'." >&2
      echo "Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
      exit 1
    fi
  fi
fi

if [[ -n "${COMPOSE_FILES:-}" ]]; then
  # shellcheck disable=SC2206
  COMPOSE_FILES_LIST=(${COMPOSE_FILES})
elif [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 ]]; then
  mapfile -t instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]}")

  append_unique_file COMPOSE_FILES_LIST "$BASE_COMPOSE_FILE"

  declare -a instance_app_names=()
  apps_raw="${COMPOSE_INSTANCE_APP_NAMES[$INSTANCE_NAME]:-}"
  if [[ -n "$apps_raw" ]]; then
    mapfile -t instance_app_names < <(printf '%s\n' "$apps_raw")
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

COMPOSE_ENV_FILES_LIST=()

if [[ -n "${COMPOSE_ENV_FILES:-}" ]]; then
  split_env_entries "${COMPOSE_ENV_FILES}" COMPOSE_ENV_FILES_LIST
fi

if (( ${#COMPOSE_ENV_FILES_LIST[@]} == 0 )); then
  if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
    COMPOSE_ENV_FILES_LIST=("$COMPOSE_ENV_FILE")
  elif [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 ]]; then
    if [[ -n "${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]:-}" ]]; then
      split_env_entries "${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]}" COMPOSE_ENV_FILES_LIST
    fi
  fi
fi

if (( ${#COMPOSE_ENV_FILES_LIST[@]} == 0 )) && [[ -n "$INSTANCE_NAME" ]]; then
  declare -a __fallback_envs=()
  if [[ -f "$REPO_ROOT/env/local/common.env" ]]; then
    __fallback_envs+=("env/local/common.env")
  elif [[ -f "$REPO_ROOT/env/common.example.env" ]]; then
    __fallback_envs+=("env/common.example.env")
  fi

  if [[ -f "$REPO_ROOT/env/local/${INSTANCE_NAME}.env" ]]; then
    __fallback_envs+=("env/local/${INSTANCE_NAME}.env")
  elif [[ -f "$REPO_ROOT/env/${INSTANCE_NAME}.example.env" ]]; then
    __fallback_envs+=("env/${INSTANCE_NAME}.example.env")
  fi

  COMPOSE_ENV_FILES_LIST=("${__fallback_envs[@]}")
  unset __fallback_envs
fi

if (( ${#COMPOSE_ENV_FILES_LIST[@]} > 0 )); then
  declare -a __filtered_env_files=()
  for __env_entry in "${COMPOSE_ENV_FILES_LIST[@]}"; do
    [[ -z "$__env_entry" ]] && continue
    __filtered_env_files+=("$__env_entry")
  done
  COMPOSE_ENV_FILES_LIST=("${__filtered_env_files[@]}")
  unset __filtered_env_files
  unset __env_entry
fi

if (( ${#COMPOSE_ENV_FILES_LIST[@]} > 0 )); then
  COMPOSE_ENV_FILE="${COMPOSE_ENV_FILES_LIST[-1]}"
  COMPOSE_ENV_FILES="$(printf '%s\n' "${COMPOSE_ENV_FILES_LIST[@]}")"
  COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
else
  COMPOSE_ENV_FILES=""
fi

declare -a COMPOSE_ENV_FILES_RESOLVED=()
if (( ${#COMPOSE_ENV_FILES_LIST[@]} > 0 )); then
  for env_file in "${COMPOSE_ENV_FILES_LIST[@]}"; do
    resolved_env_file="$env_file"
    if [[ "$resolved_env_file" != /* ]]; then
      resolved_env_file="$REPO_ROOT/$resolved_env_file"
    fi
    COMPOSE_ENV_FILES_RESOLVED+=("$resolved_env_file")
  done
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

if (( ${#COMPOSE_ENV_FILES_RESOLVED[@]} > 0 )); then
  for env_file in "${COMPOSE_ENV_FILES_RESOLVED[@]}"; do
    COMPOSE_CMD+=(--env-file "$env_file")
  done
fi

if [[ ${#COMPOSE_FILES_LIST[@]} -gt 0 ]]; then
  for file in "${COMPOSE_FILES_LIST[@]}"; do
    resolved_file="$file"
    if [[ "$resolved_file" != /* ]]; then
      resolved_file="$REPO_ROOT/$resolved_file"
    fi
    COMPOSE_CMD+=(-f "$resolved_file")
  done
fi

if [[ ${#COMPOSE_ARGS[@]} -gt 0 ]]; then
  COMPOSE_CMD+=("${COMPOSE_ARGS[@]}")
fi

exec "${COMPOSE_CMD[@]}"
