#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/build_compose_file.sh [options] <instance>

Generates a unified docker-compose.yml in the repository root by combining the
resolved manifests for an instance.

Arguments:
  instance              Instance name (e.g., core, media).

Flags:
  -h, --help            Show this help text and exit.
  -f, --file PATH       Add an extra compose file after the default plan. Can be
                        used multiple times (equivalent to COMPOSE_EXTRA_FILES).
  -e, --env-file PATH   Add an extra .env to the applied chain (equivalent to
                        COMPOSE_ENV_FILES). Can be used multiple times.
  -o, --output PATH     Output path (default: ./docker-compose.yml).
  -n, --env-output PATH Consolidated .env path (default: ./.env).

Relevant environment variables:
  COMPOSE_EXTRA_FILES  Extra compose files applied after the default plan.
  COMPOSE_ENV_FILES    Explicit env chain; replaces the chain discovered for the
                       instance when provided.
  DOCKER_COMPOSE_BIN   Override the docker compose binary.

The generated file can be reused by other scripts by passing
"-f docker-compose.yml" or setting COMPOSE_FILE.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_internal/lib/compose_paths.sh
source "$SCRIPT_DIR/_internal/lib/compose_paths.sh"

if ! REPO_ROOT="$(compose_common__resolve_repo_root)"; then
  exit 1
fi

# shellcheck source=_internal/lib/compose_command.sh
source "$SCRIPT_DIR/_internal/lib/compose_command.sh"
# shellcheck source=_internal/lib/compose_plan.sh
source "$SCRIPT_DIR/_internal/lib/compose_plan.sh"
# shellcheck source=_internal/lib/compose_env_chain.sh
source "$SCRIPT_DIR/_internal/lib/compose_env_chain.sh"
# shellcheck source=_internal/lib/compose_env_validation.sh
source "$SCRIPT_DIR/_internal/lib/compose_env_validation.sh"
# shellcheck source=_internal/lib/env_file_chain.sh
source "$SCRIPT_DIR/_internal/lib/env_file_chain.sh"

INSTANCE_NAME=""
OUTPUT_FILE="$REPO_ROOT/docker-compose.yml"
ENV_OUTPUT_FILE="$REPO_ROOT/.env"
GENERATED_HEADER="# GENERATED FILE. DO NOT EDIT. RE-RUN SCRIPTS/BUILD_COMPOSE_FILE.SH OR SCRIPTS/DEPLOY_INSTANCE.SH."
declare -a DECLARE_EXTRAS=()
declare -a EXPLICIT_ENV_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
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
  -*)
    echo "Error: unknown argument '$1'." >&2
    exit 64
    ;;
  *)
    break
    ;;
  esac
  shift
done

if [[ $# -lt 1 ]]; then
  echo "Error: instance argument is required." >&2
  exit 64
fi

if [[ $# -gt 1 ]]; then
  echo "Error: unexpected argument '$2'." >&2
  exit 64
fi

INSTANCE_NAME="$1"

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

if ! compose_metadata="$("$SCRIPT_DIR/_internal/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "Error: could not load instance metadata." >&2
  exit 1
fi

eval "$compose_metadata"

if [[ ! -v COMPOSE_INSTANCE_FILES[$INSTANCE_NAME] ]]; then
  echo "Error: unknown instance '$INSTANCE_NAME'." >&2
  echo "Available: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
  exit 1
fi

declare -a plan_files=()
if build_compose_file_plan "$INSTANCE_NAME" plan_files EXTRA_COMPOSE_FILES; then
  compose_files_list=("${plan_files[@]}")
else
  echo "Error: failed to build the compose file list for '$INSTANCE_NAME'." >&2
  exit 1
fi

if ((${#compose_files_list[@]} == 0)); then
  echo "Error: compose file list is empty." >&2
  exit 1
fi

declare -a COMPOSE_ENV_FILES_LIST=()
declare -a COMPOSE_ENV_FILES_RESOLVED=()
if ! compose_env_chain__resolve \
  "$REPO_ROOT" \
  "$INSTANCE_NAME" \
  "${COMPOSE_ENV_FILES:-}" \
  COMPOSE_ENV_FILES_LIST \
  COMPOSE_ENV_FILES_RESOLVED \
  "${EXPLICIT_ENV_FILES[@]}"; then
  exit 1
fi

printf 'Resolved env chain (order):\n'
if ((${#COMPOSE_ENV_FILES_RESOLVED[@]} > 0)); then
  printf '  - %s\n' "${COMPOSE_ENV_FILES_RESOLVED[@]}"
else
  printf '  (none)\n'
fi

declare -A env_loaded=()
if ! compose_env_chain__load_env_files "$SCRIPT_DIR" env_loaded "${COMPOSE_ENV_FILES_RESOLVED[@]}"; then
  exit 1
fi

if ! compose_env_validation__check "$REPO_ROOT" compose_files_list env_loaded COMPOSE_ENV_FILES_LIST; then
  exit 1
fi

if [[ -n "${env_loaded[REPO_ROOT]:-}" ]]; then
  echo "Error: REPO_ROOT must not be set in env files; it is derived by scripts." >&2
  exit 1
fi

if [[ -n "${env_loaded[LOCAL_INSTANCE]:-}" ]]; then
  echo "Error: LOCAL_INSTANCE must not be set in env files; it is derived by scripts." >&2
  exit 1
fi

if [[ -n "${env_loaded[APP_DATA_DIR]:-}" || -n "${env_loaded[APP_DATA_DIR_MOUNT]:-}" ]]; then
  echo "Error: APP_DATA_DIR and APP_DATA_DIR_MOUNT are no longer supported." >&2
  exit 1
fi

if ! cd "$REPO_ROOT"; then
  echo "Error: could not access repository directory: $REPO_ROOT" >&2
  exit 1
fi

if ! env_file_chain__merge_to_file \
  "$ENV_OUTPUT_FILE" \
  "$GENERATED_HEADER" \
  "${COMPOSE_ENV_FILES_RESOLVED[@]}"; then
  exit 1
fi
printf 'REPO_ROOT=%s\n' "$REPO_ROOT" >>"$ENV_OUTPUT_FILE"
printf 'LOCAL_INSTANCE=%s\n' "$INSTANCE_NAME" >>"$ENV_OUTPUT_FILE"

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

compose_tmp_file="${OUTPUT_FILE}.tmp"
trap 'rm -f "$compose_tmp_file"' EXIT
compose_tmp_dir="$(dirname "$compose_tmp_file")"
if [[ ! -d "$compose_tmp_dir" ]]; then
  if ! mkdir -p "$compose_tmp_dir"; then
    echo "Error: could not create temporary compose directory: $compose_tmp_dir" >&2
    exit 1
  fi
fi
: >"$compose_tmp_file"

generate_cmd=(env REPO_ROOT="$REPO_ROOT" LOCAL_INSTANCE="$INSTANCE_NAME" "${compose_cmd[@]}" config --output "$compose_tmp_file")

if ! "${generate_cmd[@]}"; then
  echo "Error: failed to generate docker-compose.yml." >&2
  exit 1
fi
{
  printf '%s\n' "$GENERATED_HEADER"
  cat "$compose_tmp_file"
} >"$OUTPUT_FILE"
validate_cmd=(env REPO_ROOT="$REPO_ROOT" LOCAL_INSTANCE="$INSTANCE_NAME" "${compose_cmd[@]}" -f "$OUTPUT_FILE" config -q)
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
