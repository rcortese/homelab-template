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

if [[ -n "${COMPOSE_FILES:-}" ]]; then
  # shellcheck disable=SC2206
  COMPOSE_FILES_LIST=(${COMPOSE_FILES})
elif [[ -n "$INSTANCE_NAME" ]]; then
  if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
    echo "Error: não foi possível carregar metadados das instâncias." >&2
    exit 1
  fi

  eval "$compose_metadata"

  if [[ -z "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]:-}" ]]; then
    echo "Error: instância desconhecida '$INSTANCE_NAME'." >&2
    echo "Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
    exit 1
  fi

  mapfile -t instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$INSTANCE_NAME]}")
  COMPOSE_FILES_LIST=("$BASE_COMPOSE_FILE")

  for compose_file in "${instance_compose_files[@]}"; do
    [[ -z "$compose_file" ]] && continue
    COMPOSE_FILES_LIST+=("$compose_file")
  done
fi

if [[ -z "${COMPOSE_ENV_FILE:-}" && -n "$INSTANCE_NAME" ]]; then
  maybe_env_file="env/local/${INSTANCE_NAME}.env"
  if [[ -f "$maybe_env_file" ]]; then
    COMPOSE_ENV_FILE="$maybe_env_file"
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

if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
  env_file="$COMPOSE_ENV_FILE"
  if [[ "$env_file" != /* ]]; then
    env_file="$REPO_ROOT/$env_file"
  fi
  COMPOSE_CMD+=(--env-file "$env_file")
fi

if [[ ${#COMPOSE_FILES_LIST[@]} -gt 0 ]]; then
  for file in "${COMPOSE_FILES_LIST[@]}"; do
    COMPOSE_CMD+=(-f "$file")
  done
fi

if [[ ${#COMPOSE_ARGS[@]} -gt 0 ]]; then
  COMPOSE_CMD+=("${COMPOSE_ARGS[@]}")
fi

exec "${COMPOSE_CMD[@]}"
