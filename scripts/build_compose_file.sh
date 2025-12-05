#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

print_help() {
  cat <<'USAGE'
Uso: scripts/build_compose_file.sh [opções]

Gera um docker-compose.yml unificado na raiz do repositório combinando os
manifests resolvidos para uma instância.

Flags:
  -h, --help            Exibe esta ajuda e sai.
  -i, --instance NAME   Seleciona a instância (ex.: core, media).
  -f, --file PATH       Adiciona um compose extra após o plano padrão. Pode ser
                        usado múltiplas vezes (equivale a COMPOSE_EXTRA_FILES).
  -e, --env-file PATH   Adiciona um .env extra à cadeia aplicada (equivale a
                        COMPOSE_ENV_FILES/COMPOSE_ENV_FILE). Pode ser usado
                        múltiplas vezes.
  -o, --output PATH     Caminho de saída (default: ./docker-compose.yml).

Variáveis de ambiente relevantes:
  COMPOSE_FILES        Sobrescreve a lista -f aplicada (separada por espaços
                       ou vírgulas). Se definida, ignora o plano por instância.
  COMPOSE_EXTRA_FILES  Compose extras aplicados após o plano padrão.
  COMPOSE_ENV_FILES    Cadeia explícita de envs; substitui a cadeia descoberta
                       pela instância quando informada.
  COMPOSE_ENV_FILE     Alias para COMPOSE_ENV_FILES quando único arquivo.
  DOCKER_COMPOSE_BIN   Sobrescreve o binário docker compose.

O arquivo gerado pode ser reutilizado por outros scripts passando
"-f docker-compose.yml" ou definindo COMPOSE_FILE.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"
# shellcheck source=lib/compose_plan.sh
source "$SCRIPT_DIR/lib/compose_plan.sh"
# shellcheck source=lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

INSTANCE_NAME=""
OUTPUT_FILE="$REPO_ROOT/docker-compose.yml"
declare -a DECLARE_EXTRAS=()
declare -a EXPLICIT_ENV_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  -i | --instance)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --instance requer um valor." >&2
      exit 64
    fi
    INSTANCE_NAME="$1"
    ;;
  -f | --file)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --file requer um caminho." >&2
      exit 64
    fi
    DECLARE_EXTRAS+=("$1")
    ;;
  -e | --env-file)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --env-file requer um caminho." >&2
      exit 64
    fi
    EXPLICIT_ENV_FILES+=("$1")
    ;;
  -o | --output)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --output requer um caminho." >&2
      exit 64
    fi
    OUTPUT_FILE="$1"
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Error: argumento desconhecido '$1'." >&2
    exit 64
    ;;
  esac
  shift
done

if [[ "$OUTPUT_FILE" != /* ]]; then
  OUTPUT_FILE="$REPO_ROOT/$OUTPUT_FILE"
fi

declare -a EXTRA_COMPOSE_FILES=()
mapfile -t EXTRA_COMPOSE_FILES < <(
  env_file_chain__parse_list "${COMPOSE_EXTRA_FILES:-}"
)
if ((${#DECLARE_EXTRAS[@]} > 0)); then
  EXTRA_COMPOSE_FILES+=("${DECLARE_EXTRAS[@]}")
fi

declare -a compose_files_list=()
metadata_loaded=0

if [[ -n "$INSTANCE_NAME" && -z "${COMPOSE_FILES:-}" ]]; then
  if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
    echo "Error: não foi possível carregar metadados das instâncias." >&2
    exit 1
  fi

  eval "$compose_metadata"
  metadata_loaded=1

  if [[ ! -v COMPOSE_INSTANCE_FILES[$INSTANCE_NAME] ]]; then
    echo "Error: instância desconhecida '$INSTANCE_NAME'." >&2
    echo "Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
    exit 1
  fi
fi

if [[ -n "${COMPOSE_FILES:-}" ]]; then
  # shellcheck disable=SC2206
  compose_files_list=(${COMPOSE_FILES})
  if ((${#EXTRA_COMPOSE_FILES[@]} > 0)); then
    compose_files_list+=("${EXTRA_COMPOSE_FILES[@]}")
  fi
elif [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 ]]; then
  declare -a plan_files=()
  if build_compose_file_plan "$INSTANCE_NAME" plan_files EXTRA_COMPOSE_FILES; then
    compose_files_list=("${plan_files[@]}")
  else
    echo "Error: falha ao montar a lista de compose files para '$INSTANCE_NAME'." >&2
    exit 1
  fi
else
  echo "Error: nenhuma instância informada e COMPOSE_FILES vazio." >&2
  exit 64
fi

if ((${#compose_files_list[@]} == 0)); then
  echo "Error: lista de compose files está vazia." >&2
  exit 1
fi

explicit_env_input="${COMPOSE_ENV_FILES:-}"
if [[ -z "$explicit_env_input" && -n "${COMPOSE_ENV_FILE:-}" ]]; then
  explicit_env_input="$COMPOSE_ENV_FILE"
fi

if ((${#EXPLICIT_ENV_FILES[@]} > 0)); then
  cli_env_join="$(env_file_chain__join ' ' "${EXPLICIT_ENV_FILES[@]}")"
  if [[ -n "$explicit_env_input" ]]; then
    explicit_env_input+=" $cli_env_join"
  else
    explicit_env_input="$cli_env_join"
  fi
fi

metadata_env_input=""
if [[ -n "$INSTANCE_NAME" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]:-}" ]]; then
  metadata_env_input="${COMPOSE_INSTANCE_ENV_FILES[$INSTANCE_NAME]}"
fi

declare -a COMPOSE_ENV_FILES_LIST=()
if [[ -n "$explicit_env_input" || -n "$metadata_env_input" ]]; then
  mapfile -t COMPOSE_ENV_FILES_LIST < <(
    env_file_chain__resolve_explicit "$explicit_env_input" "$metadata_env_input"
  )
fi

if ((${#COMPOSE_ENV_FILES_LIST[@]} == 0)) && [[ -n "$INSTANCE_NAME" ]]; then
  mapfile -t COMPOSE_ENV_FILES_LIST < <(
    env_file_chain__defaults "$REPO_ROOT" "$INSTANCE_NAME"
  )
fi

declare -a COMPOSE_ENV_FILES_RESOLVED=()
if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  mapfile -t COMPOSE_ENV_FILES_RESOLVED < <(
    env_file_chain__to_absolute "$REPO_ROOT" "${COMPOSE_ENV_FILES_LIST[@]}"
  )
fi

if ! cd "$REPO_ROOT"; then
  echo "Error: não foi possível acessar o diretório do repositório: $REPO_ROOT" >&2
  exit 1
fi

declare -a compose_cmd=()
if ! compose_resolve_command compose_cmd; then
  exit $?
fi

if ((${#COMPOSE_ENV_FILES_RESOLVED[@]} > 0)); then
  for env_file in "${COMPOSE_ENV_FILES_RESOLVED[@]}"; do
    compose_cmd+=(--env-file "$env_file")
  done
fi

for compose_file in "${compose_files_list[@]}"; do
  resolved_file="$compose_file"
  if [[ "$resolved_file" != /* ]]; then
    resolved_file="$REPO_ROOT/$resolved_file"
  fi
  compose_cmd+=(-f "$resolved_file")
done

generate_cmd=("${compose_cmd[@]}" config --output "$OUTPUT_FILE")

if ! "${generate_cmd[@]}"; then
  echo "Error: falha ao gerar docker-compose.yml." >&2
  exit 1
fi
validate_cmd=("${compose_cmd[@]}" -f "$OUTPUT_FILE" config -q)
if ! "${validate_cmd[@]}"; then
  echo "Error: inconsistências detectadas ao validar $OUTPUT_FILE." >&2
  exit 1
fi

printf 'docker-compose.yml gerado em: %s\n' "$OUTPUT_FILE"
printf 'Arquivos de compose aplicados (ordem):\n'
printf '  - %s\n' "${compose_files_list[@]}"
if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  printf 'Cadeia de env aplicada (ordem):\n'
  printf '  - %s\n' "${COMPOSE_ENV_FILES_LIST[@]}"
fi

exit 0
