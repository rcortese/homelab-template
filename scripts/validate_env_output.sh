#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/validate_env_output.sh [options] [instance]

Validates that the generated root .env matches the env/local chain for an
instance (env/local/common.env -> env/local/<instance>.env). The comparison
ignores the generated header line.

Arguments:
  instance              Optional instance name. Defaults to the first instance
                        discovered or the single entry in COMPOSE_INSTANCES.

Options:
  -h, --help            Show this help text and exit.
  -n, --env-output PATH Override the .env file to compare (default: ./.env).

Relevant environment variables:
  COMPOSE_INSTANCES     Single instance to validate (space- or comma-separated).
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

ENV_OUTPUT_FILE="$REPO_ROOT/.env"
GENERATED_HEADER="# GENERATED FILE. DO NOT EDIT. RE-RUN SCRIPTS/BUILD_COMPOSE_FILE.SH OR SCRIPTS/DEPLOY_INSTANCE.SH."

INSTANCE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
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

if [[ $# -gt 1 ]]; then
  echo "Error: unexpected argument '$2'." >&2
  exit 64
fi

if [[ $# -eq 1 ]]; then
  INSTANCE_NAME="$1"
fi

if [[ "$ENV_OUTPUT_FILE" != /* ]]; then
  ENV_OUTPUT_FILE="$REPO_ROOT/$ENV_OUTPUT_FILE"
fi

if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "Error: could not load instance metadata." >&2
  exit 1
fi

eval "$compose_metadata"

if [[ -z "$INSTANCE_NAME" ]]; then
  if [[ -n "${COMPOSE_INSTANCES:-}" ]]; then
    mapfile -t requested_instances < <(
      env_file_chain__parse_list "$COMPOSE_INSTANCES"
    )
    if ((${#requested_instances[@]} == 0)); then
      echo "Error: COMPOSE_INSTANCES did not specify an instance." >&2
      exit 1
    fi
    if ((${#requested_instances[@]} > 1)); then
      echo "Error: .env validation requires a single instance; got: ${requested_instances[*]}" >&2
      exit 1
    fi
    INSTANCE_NAME="${requested_instances[0]}"
  else
    INSTANCE_NAME="${COMPOSE_INSTANCE_NAMES[0]}"
  fi
fi

if [[ -z "$INSTANCE_NAME" ]]; then
  echo "Error: instance argument is required." >&2
  exit 64
fi

if [[ ! -v COMPOSE_INSTANCE_FILES[$INSTANCE_NAME] ]]; then
  echo "Error: unknown instance '$INSTANCE_NAME'." >&2
  echo "Available: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
  exit 1
fi

env_chain_output=""
if ! env_chain_output="$(env_file_chain__defaults "$REPO_ROOT" "$INSTANCE_NAME")"; then
  exit 1
fi
if [[ -n "$env_chain_output" ]]; then
  mapfile -t COMPOSE_ENV_FILES_LIST <<<"$env_chain_output"
else
  COMPOSE_ENV_FILES_LIST=()
fi

declare -a COMPOSE_ENV_FILES_RESOLVED=()
if ((${#COMPOSE_ENV_FILES_LIST[@]} > 0)); then
  mapfile -t COMPOSE_ENV_FILES_RESOLVED < <(
    env_file_chain__to_absolute "$REPO_ROOT" "${COMPOSE_ENV_FILES_LIST[@]}"
  )
fi

tmp_env_file="$(mktemp "${TMPDIR:-/tmp}/env-merge.${INSTANCE_NAME}.XXXXXX")"
trap 'rm -f "$tmp_env_file"' EXIT

if ! env_file_chain__merge_to_file \
  "$tmp_env_file" \
  "$GENERATED_HEADER" \
  "${COMPOSE_ENV_FILES_RESOLVED[@]}"; then
  exit 1
fi
printf 'REPO_ROOT=%s\n' "$REPO_ROOT" >>"$tmp_env_file"
printf 'LOCAL_INSTANCE=%s\n' "$INSTANCE_NAME" >>"$tmp_env_file"

if [[ ! -f "$ENV_OUTPUT_FILE" ]]; then
  echo "Error: root .env file not found at $ENV_OUTPUT_FILE." >&2
  echo "Run scripts/build_compose_file.sh $INSTANCE_NAME to generate it." >&2
  exit 1
fi

strip_generated_header() {
  local source_file="$1"
  local first_line=""

  if ! IFS= read -r first_line <"$source_file"; then
    first_line=""
  fi

  if [[ "$first_line" == "$GENERATED_HEADER" ]]; then
    tail -n +2 "$source_file"
  else
    cat "$source_file"
  fi
}

if ! diff -u <(strip_generated_header "$tmp_env_file") <(strip_generated_header "$ENV_OUTPUT_FILE"); then
  echo "Error: root .env is out of sync with env/local for instance '$INSTANCE_NAME'." >&2
  echo "Re-run scripts/build_compose_file.sh $INSTANCE_NAME to regenerate it." >&2
  exit 1
fi

printf '.env is consistent with env/local for instance: %s\n' "$INSTANCE_NAME"

exit 0
