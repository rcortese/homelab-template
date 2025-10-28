#!/usr/bin/env bash

# shellcheck source=SCRIPTDIR/compose_file_utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_file_utils.sh"

# CLI helpers for the validate_compose script.

validate_cli_print_help() {
  cat <<'HELP'
Uso: scripts/validate_compose.sh

Valida as instâncias definidas para o repositório garantindo que `docker compose config`
execute com sucesso para cada combinação de arquivos base + instância.

Argumentos posicionais:
  (nenhum)

Variáveis de ambiente relevantes:
  DOCKER_COMPOSE_BIN  Sobrescreve o comando docker compose (ex.: docker-compose).
  COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.
  COMPOSE_EXTRA_FILES Overlays extras aplicados após o override padrão (aceita espaços ou vírgulas).

Exemplos:
  scripts/validate_compose.sh
  COMPOSE_INSTANCES="media" scripts/validate_compose.sh
  COMPOSE_EXTRA_FILES="compose/overlays/metrics.yml" scripts/validate_compose.sh
  COMPOSE_INSTANCES="media" \
    COMPOSE_EXTRA_FILES="compose/overlays/logging.yml compose/overlays/metrics.yml" \
    scripts/validate_compose.sh
HELP
}

validate_cli_parse_instances() {
  local -n __out=$1
  shift

  local first_arg="${1:-}"

  if [[ -n "$first_arg" ]]; then
    case "$first_arg" in
    -h | --help)
      validate_cli_print_help
      return 2
      ;;
    *)
      echo "Argumento não reconhecido: $first_arg" >&2
      return 1
      ;;
    esac
  fi

  local -a instances=()

  if [[ -n "${COMPOSE_INSTANCES:-}" ]]; then
    IFS=',' read -ra raw_instances <<<"$COMPOSE_INSTANCES"
    local entry token
    for entry in "${raw_instances[@]}"; do
      entry="$(trim "$entry")"
      [[ -z "$entry" ]] && continue
      for token in $entry; do
        token="$(trim "$token")"
        [[ -z "$token" ]] && continue
        instances+=("$token")
      done
    done
  else
    instances=("${COMPOSE_INSTANCE_NAMES[@]}")
  fi

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo "Error: nenhuma instância informada para validação." >&2
    return 1
  fi

  __out=("${instances[@]}")
  return 0
}
