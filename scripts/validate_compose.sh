#!/usr/bin/env bash
# Usage: scripts/validate_compose.sh
#
# Arguments:
#   (nenhum) — o script valida as instâncias conhecidas usando somente base + override da instância.
# Environment:
#   DOCKER_COMPOSE_BIN  Sobrescreve o binário usado (ex.: docker-compose).
#   COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.
# Examples:
#   scripts/validate_compose.sh
#   COMPOSE_INSTANCES="media" scripts/validate_compose.sh
set -euo pipefail

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Uso: scripts/validate_compose.sh

Valida as instâncias definidas para o repositório garantindo que `docker compose config`
execute com sucesso para cada combinação de arquivos base + instância.

Argumentos posicionais:
  (nenhum)

Variáveis de ambiente relevantes:
  DOCKER_COMPOSE_BIN  Sobrescreve o comando docker compose (ex.: docker-compose).
  COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.

Exemplos:
  scripts/validate_compose.sh
  COMPOSE_INSTANCES="media" scripts/validate_compose.sh
EOF
  exit 0
  ;;
"") ;; # continuar execução normal
*)
  echo "Argumento não reconhecido: $1" >&2
  exit 1
  ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_LOADER="$SCRIPT_DIR/lib/env_loader.sh"

if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "Error: não foi possível carregar metadados das instâncias." >&2
  exit 1
fi

eval "$compose_metadata"

if [[ -n "${DOCKER_COMPOSE_BIN:-}" ]]; then
  # Allow overriding the docker compose binary (e.g., "docker-compose").
  # shellcheck disable=SC2206
  compose_cmd=(${DOCKER_COMPOSE_BIN})
else
  compose_cmd=(docker compose)
fi

if ! command -v "${compose_cmd[0]}" >/dev/null 2>&1; then
  echo "Error: ${compose_cmd[0]} is not available. Set DOCKER_COMPOSE_BIN if needed." >&2
  exit 127
fi

base_file="$REPO_ROOT/$BASE_COMPOSE_FILE"

status=0

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

parse_compose_file_list() {
  local raw="$1"
  local entry

  raw="${raw//,/ }"

  for entry in $raw; do
    entry="$(trim "$entry")"
    [[ -z "$entry" ]] && continue
    printf '%s\n' "$entry"
  done
}

resolve_compose_file() {
  local candidate="$1"

  if [[ "$candidate" == /* ]]; then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "$REPO_ROOT/${candidate#./}"
  fi
}

declare -a instances_to_validate=()

if [[ -n "${COMPOSE_INSTANCES:-}" ]]; then
  IFS=',' read -ra raw_instances <<<"$COMPOSE_INSTANCES"
  for entry in "${raw_instances[@]}"; do
    entry="$(trim "$entry")"
    [[ -z "$entry" ]] && continue
    for token in $entry; do
      token="$(trim "$token")"
      [[ -z "$token" ]] && continue
      instances_to_validate+=("$token")
    done
  done
else
  instances_to_validate=("${COMPOSE_INSTANCE_NAMES[@]}")
fi

if [[ ${#instances_to_validate[@]} -eq 0 ]]; then
  echo "Error: nenhuma instância informada para validação." >&2
  exit 1
fi

declare -A seen
for instance in "${instances_to_validate[@]}"; do
  if [[ -z "$instance" ]]; then
    continue
  fi
  if [[ -n "${seen[$instance]:-}" ]]; then
    continue
  fi
  seen[$instance]=1

  instance_files_raw="${COMPOSE_INSTANCE_FILES[$instance]:-}"
  if [[ -z "$instance_files_raw" ]]; then
    mapfile -t potential_matches < <(
      find "$REPO_ROOT/compose/apps" -mindepth 2 -maxdepth 2 -name "${instance}.yml" -print 2>/dev/null
    )

    if [[ ${#potential_matches[@]} -gt 0 ]]; then
      echo "✖ instância=\"$instance\" (combinação de arquivos ausente nos metadados)" >&2
      status=1
      continue
    fi

    local_candidate="$REPO_ROOT/env/local/${instance}.env"
    template_candidate="$REPO_ROOT/env/${instance}.example.env"
    if [[ -f "$local_candidate" || -f "$template_candidate" ]]; then
      echo "✖ instância=\"$instance\" (arquivo ausente: compose/apps/*/${instance}.yml)" >&2
      status=1
      continue
    fi

    echo "Error: instância desconhecida '$instance'." >&2
    exit 1
  fi

  mapfile -t instance_file_list < <(printf '%s\n' "$instance_files_raw")
  env_file_rel="${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}"
  env_file=""

  if [[ -n "$env_file_rel" ]]; then
    env_file="$REPO_ROOT/$env_file_rel"
  fi

  files=("$base_file")
  args=()
  missing=0

  extra_files_source=""
  extra_files=()

  if [[ -n "${COMPOSE_EXTRA_FILES+x}" ]]; then
    extra_files_source="$COMPOSE_EXTRA_FILES"
  elif [[ -n "$env_file_rel" && -f "$env_file" ]]; then
    if extra_output="$("$ENV_LOADER" "$env_file" COMPOSE_EXTRA_FILES)" && [[ -n "$extra_output" ]]; then
      extra_files_source="${extra_output#COMPOSE_EXTRA_FILES=}"
    fi
  fi

  if [[ -n "$extra_files_source" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      extra_files+=("$entry")
    done < <(parse_compose_file_list "$extra_files_source")
  fi

  for rel in "${instance_file_list[@]}"; do
    [[ -z "$rel" ]] && continue
    files+=("$(resolve_compose_file "$rel")")
  done

  if [[ ${#extra_files[@]} -gt 0 ]]; then
    for extra in "${extra_files[@]}"; do
      files+=("$(resolve_compose_file "$extra")")
    done
  fi

  for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "✖ instância=\"$instance\" (arquivo ausente: $file)" >&2
      missing=1
      status=1
      continue
    fi
    args+=("-f" "$file")
  done

  ((missing == 1)) && continue

  env_args=()
  if [[ -n "$env_file_rel" && -f "$env_file" ]]; then
    env_args=("--env-file" "$env_file")
  fi

  echo "==> Validando $instance"
  if "${compose_cmd[@]}" "${env_args[@]}" "${args[@]}" config >/dev/null; then
    echo "✔ $instance"
  else
    echo "✖ instância=\"$instance\"" >&2
    echo "   files: ${files[*]}" >&2
    status=1
  fi
done

exit $status
