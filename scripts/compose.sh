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

# shellcheck source=./lib/compose_plan.sh
source "$SCRIPT_DIR/lib/compose_plan.sh"

# shellcheck source=./lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

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
declare -a EXTRA_COMPOSE_FILES=()

mapfile -t EXTRA_COMPOSE_FILES < <(
  env_file_chain__parse_list "${COMPOSE_EXTRA_FILES:-}"
)

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
  if ((${#EXTRA_COMPOSE_FILES[@]} > 0)); then
    COMPOSE_FILES_LIST+=("${EXTRA_COMPOSE_FILES[@]}")
  fi
elif [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 ]]; then
  declare -a plan_files=()
  declare -A plan_metadata=()

  if build_compose_file_plan "$INSTANCE_NAME" plan_files EXTRA_COMPOSE_FILES plan_metadata; then
    COMPOSE_FILES_LIST=("${plan_files[@]}")

    if [[ -n "${plan_metadata[app_names]:-}" ]]; then
      mapfile -t resolved_instance_app_names < <(printf '%s\n' "${plan_metadata[app_names]}")
    fi
  fi
fi

COMPOSE_ENV_FILES_LIST=()
explicit_env_input="${COMPOSE_ENV_FILES:-}"
if [[ -z "$explicit_env_input" && -n "${COMPOSE_ENV_FILE:-}" ]]; then
  explicit_env_input="$COMPOSE_ENV_FILE"
fi

metadata_env_input=""
if [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]:-}" ]]; then
  metadata_env_input="${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]}"
fi

if [[ -n "$explicit_env_input" || -n "$metadata_env_input" ]]; then
  mapfile -t COMPOSE_ENV_FILES_LIST < <(
    env_file_chain__resolve_explicit "$explicit_env_input" "$metadata_env_input"
  )
else
  COMPOSE_ENV_FILES_LIST=()
fi

if ((${#COMPOSE_ENV_FILES_LIST[@]} == 0)) && [[ -n "$INSTANCE_NAME" ]]; then
  mapfile -t COMPOSE_ENV_FILES_LIST < <(
    env_file_chain__defaults "$REPO_ROOT" "$INSTANCE_NAME"
  )
fi

if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  COMPOSE_ENV_FILE="${COMPOSE_ENV_FILES_LIST[-1]}"
  COMPOSE_ENV_FILES="$(printf '%s\n' "${COMPOSE_ENV_FILES_LIST[@]}")"
  COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
else
  COMPOSE_ENV_FILES=""
fi

declare -a COMPOSE_ENV_FILES_RESOLVED=()
if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  mapfile -t COMPOSE_ENV_FILES_RESOLVED < <(
    env_file_chain__to_absolute "$REPO_ROOT" "${COMPOSE_ENV_FILES_LIST[@]}"
  )
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

if ((${#COMPOSE_ENV_FILES_RESOLVED[@]} > 0)); then
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

if [[ -n "$app_data_dir_value" ]]; then
  APP_DATA_DIR="$app_data_dir_value" exec -- "${COMPOSE_CMD[@]}"
else
  exec "${COMPOSE_CMD[@]}"
fi
