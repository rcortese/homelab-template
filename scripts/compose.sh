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

# shellcheck source=./lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=./lib/compose_plan.sh
source "$SCRIPT_DIR/lib/compose_plan.sh"

# shellcheck source=./lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

# shellcheck source=./lib/env_helpers.sh
source "$SCRIPT_DIR/lib/env_helpers.sh"

INSTANCE_NAME=""
COMPOSE_ARGS=()
declare -a COMPOSE_CMD=()

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

    if [[ ! -v COMPOSE_INSTANCE_FILES[$INSTANCE_NAME] ]]; then
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

service_name_value="${SERVICE_NAME:-}"
app_data_dir_value="${APP_DATA_DIR:-}"
app_data_dir_mount_value="${APP_DATA_DIR_MOUNT:-}"

if [[ (-z "$service_name_value" || -z "$app_data_dir_value" || -z "$app_data_dir_mount_value") && -n "$compose_env_file_abs" && -f "$compose_env_file_abs" ]]; then
  if app_data_dir_kv="$("$SCRIPT_DIR/lib/env_loader.sh" "$compose_env_file_abs" SERVICE_NAME APP_DATA_DIR APP_DATA_DIR_MOUNT)"; then
    if [[ -n "$app_data_dir_kv" ]]; then
      while IFS= read -r env_line; do
        if [[ -z "$env_line" ]]; then
          continue
        fi
        case "$env_line" in
        SERVICE_NAME=*)
          if [[ -z "$service_name_value" ]]; then
            service_name_value="${env_line#SERVICE_NAME=}"
          fi
          ;;
        APP_DATA_DIR=*)
          if [[ -z "$app_data_dir_value" ]]; then
            app_data_dir_value="${env_line#APP_DATA_DIR=}"
          fi
          ;;
        APP_DATA_DIR_MOUNT=*)
          if [[ -z "$app_data_dir_mount_value" ]]; then
            app_data_dir_mount_value="${env_line#APP_DATA_DIR_MOUNT=}"
          fi
          ;;
        esac
      done <<<"$app_data_dir_kv"
    fi
  fi
fi

primary_app_name=""
if [[ $metadata_loaded -eq 1 && ${#resolved_instance_app_names[@]} -gt 0 ]]; then
  primary_app_name="${resolved_instance_app_names[0]}"
fi

default_app_data_dir=""
if [[ -n "$primary_app_name" && -n "$INSTANCE_NAME" ]]; then
  default_app_data_dir="data/${primary_app_name}-${INSTANCE_NAME}"
fi

if [[ -z "$service_name_value" && -n "$primary_app_name" && -n "$INSTANCE_NAME" ]]; then
  service_name_value="${primary_app_name}-${INSTANCE_NAME}"
fi

derived_app_data_dir=""
derived_app_data_dir_mount=""
precomputed_values=0

if [[ -n "$service_name_value" && -n "$app_data_dir_value" && -n "$app_data_dir_mount_value" ]]; then
  temp_app_data_dir=""
  temp_app_data_mount=""
  if env_helpers__derive_app_data_paths "$REPO_ROOT" "$service_name_value" "$default_app_data_dir" "$app_data_dir_value" "" temp_app_data_dir temp_app_data_mount; then
    if [[ -n "$temp_app_data_mount" && "$temp_app_data_mount" == "$app_data_dir_mount_value" ]]; then
      derived_app_data_dir="$temp_app_data_dir"
      derived_app_data_dir_mount="$app_data_dir_mount_value"
      precomputed_values=1
    fi
  fi

  if ((precomputed_values == 0)); then
    temp_app_data_dir=""
    temp_app_data_mount=""
    if env_helpers__derive_app_data_paths "$REPO_ROOT" "$service_name_value" "$default_app_data_dir" "" "$app_data_dir_mount_value" temp_app_data_dir temp_app_data_mount; then
      if [[ -n "$temp_app_data_mount" && "$temp_app_data_mount" == "$app_data_dir_mount_value" ]]; then
        if [[ -z "$temp_app_data_dir" ]]; then
          temp_app_data_dir="$app_data_dir_value"
        fi
        derived_app_data_dir="$temp_app_data_dir"
        derived_app_data_dir_mount="$temp_app_data_mount"
        precomputed_values=1
      fi
    fi
  fi

  if ((precomputed_values == 0)); then
    echo "Error: APP_DATA_DIR e APP_DATA_DIR_MOUNT não podem ser definidos simultaneamente." >&2
    exit 1
  fi

  app_data_dir_value="$derived_app_data_dir"
  app_data_dir_mount_value="$derived_app_data_dir_mount"
fi

should_derive=0
if [[ -n "$INSTANCE_NAME" && -n "$service_name_value" ]]; then
  if [[ -n "$default_app_data_dir" || -n "$app_data_dir_value" || -n "$app_data_dir_mount_value" ]]; then
    should_derive=1
  fi
fi

if ((precomputed_values == 1)); then
  should_derive=0
elif ((should_derive == 1)); then
  if ! env_helpers__derive_app_data_paths "$REPO_ROOT" "$service_name_value" "$default_app_data_dir" "$app_data_dir_value" "$app_data_dir_mount_value" derived_app_data_dir derived_app_data_dir_mount; then
    exit 1
  fi
else
  derived_app_data_dir="$app_data_dir_value"
  derived_app_data_dir_mount="$app_data_dir_mount_value"
fi

if ! cd "$REPO_ROOT"; then
  echo "Error: não foi possível acessar o diretório do repositório: $REPO_ROOT" >&2
  exit 1
fi

if ! compose_resolve_command COMPOSE_CMD; then
  exit $?
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

declare -a env_prefix=()
if [[ -n "$service_name_value" ]]; then
  env_prefix+=("SERVICE_NAME=$service_name_value")
fi
if [[ -n "$derived_app_data_dir" ]]; then
  env_prefix+=("APP_DATA_DIR=$derived_app_data_dir")
fi
if [[ -n "$derived_app_data_dir_mount" ]]; then
  env_prefix+=("APP_DATA_DIR_MOUNT=$derived_app_data_dir_mount")
fi

if ((${#env_prefix[@]} > 0)); then
  exec env "${env_prefix[@]}" "${COMPOSE_CMD[@]}"
else
  exec "${COMPOSE_CMD[@]}"
fi
