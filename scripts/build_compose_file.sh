#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/build_compose_file.sh [options]

Generates a unified docker-compose.yml in the repository root by combining the
resolved manifests for an instance.

Flags:
  -h, --help            Show this help text and exit.
  -i, --instance NAME   Select the instance (e.g., core, media).
  -f, --file PATH       Add an extra compose file after the default plan. Can be
                        used multiple times (equivalent to COMPOSE_EXTRA_FILES).
  -e, --env-file PATH   Add an extra .env to the applied chain (equivalent to
                        COMPOSE_ENV_FILES). Can be used multiple times.
  -o, --output PATH     Output path (default: ./docker-compose.yml).
  -n, --env-output PATH Consolidated .env path (default: ./.env).

Relevant environment variables:
  COMPOSE_FILES        Overrides the -f list (space- or comma-separated). If set,
                       it ignores the instance plan.
  COMPOSE_EXTRA_FILES  Extra compose files applied after the default plan.
  COMPOSE_ENV_FILES    Explicit env chain; replaces the chain discovered for the
                       instance when provided.
  DOCKER_COMPOSE_BIN   Override the docker compose binary.

The generated file can be reused by other scripts by passing
"-f docker-compose.yml" or setting COMPOSE_FILE.
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
ENV_OUTPUT_FILE="$REPO_ROOT/.env"
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
      echo "Error: --instance requires a value." >&2
      exit 64
    fi
    INSTANCE_NAME="$1"
    ;;
  -f | --file)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --file requires a path." >&2
      exit 64
    fi
    DECLARE_EXTRAS+=("$1")
    ;;
  -e | --env-file)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --env-file requires a path." >&2
      exit 64
    fi
    EXPLICIT_ENV_FILES+=("$1")
    ;;
  -o | --output)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --output requires a path." >&2
      exit 64
    fi
    OUTPUT_FILE="$1"
    ;;
  -n | --env-output)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --env-output requires a path." >&2
      exit 64
    fi
    ENV_OUTPUT_FILE="$1"
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Error: unknown argument '$1'." >&2
    exit 64
    ;;
  esac
  shift
done

if [[ "$OUTPUT_FILE" != /* ]]; then
  OUTPUT_FILE="$REPO_ROOT/$OUTPUT_FILE"
fi
if [[ "$ENV_OUTPUT_FILE" != /* ]]; then
  ENV_OUTPUT_FILE="$REPO_ROOT/$ENV_OUTPUT_FILE"
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
    echo "Error: could not load instance metadata." >&2
    exit 1
  fi

  eval "$compose_metadata"
  metadata_loaded=1

  if [[ ! -v COMPOSE_INSTANCE_FILES[$INSTANCE_NAME] ]]; then
    echo "Error: unknown instance '$INSTANCE_NAME'." >&2
    echo "Available: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
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
    echo "Error: failed to build the compose file list for '$INSTANCE_NAME'." >&2
    exit 1
  fi
else
  echo "Error: no instance provided and COMPOSE_FILES is empty." >&2
  exit 64
fi

if ((${#compose_files_list[@]} == 0)); then
  echo "Error: compose file list is empty." >&2
  exit 1
fi

explicit_env_input="${COMPOSE_ENV_FILES:-}"

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

merge_env_chain_to_file() {
  local output_path="$1"
  shift

  local -a env_chain=("$@")
  local env_file line key value
  declare -A kv=()
  declare -a key_order=()

  local output_dir
  output_dir="$(dirname "$output_path")"
  if [[ ! -d "$output_dir" ]]; then
    if ! mkdir -p "$output_dir"; then
      echo "Error: could not create the .env output directory: $output_dir" >&2
      return 1
    fi
  fi

  : >"$output_path"

  for env_file in "${env_chain[@]}"; do
    if [[ ! -f "$env_file" ]]; then
      echo "Error: env file not found: $env_file" >&2
      return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" == export\ * ]]; then
        line="${line#export }"
      fi
      if [[ "$line" != *"="* ]]; then
        continue
      fi

      key="${line%%=*}"
      value="${line#*=}"

      if [[ ! -v kv[$key] ]]; then
        key_order+=("$key")
      fi
      kv[$key]="$value"
    done <"$env_file"
  done

  local ordered_key
  for ordered_key in "${key_order[@]}"; do
    printf '%s=%s\n' "$ordered_key" "${kv[$ordered_key]}" >>"$output_path"
  done
}

if ! cd "$REPO_ROOT"; then
  echo "Error: could not access repository directory: $REPO_ROOT" >&2
  exit 1
fi

if ((${#COMPOSE_ENV_FILES_RESOLVED[@]} > 0)); then
  if ! merge_env_chain_to_file "$ENV_OUTPUT_FILE" "${COMPOSE_ENV_FILES_RESOLVED[@]}"; then
    exit 1
  fi
else
  : >"$ENV_OUTPUT_FILE"
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
  echo "Error: failed to generate docker-compose.yml." >&2
  exit 1
fi
validate_cmd=("${compose_cmd[@]}" -f "$OUTPUT_FILE" config -q)
if ! "${validate_cmd[@]}"; then
  echo "Error: inconsistencies detected while validating $OUTPUT_FILE." >&2
  exit 1
fi

printf 'docker-compose.yml generated at: %s\n' "$OUTPUT_FILE"
printf 'Applied compose files (order):\n'
printf '  - %s\n' "${compose_files_list[@]}"
if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  printf 'Applied env chain (order):\n'
  printf '  - %s\n' "${COMPOSE_ENV_FILES_LIST[@]}"
fi
printf 'Consolidated .env file at: %s\n' "$ENV_OUTPUT_FILE"

exit 0
