#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/deploy_instance.sh <instance>
#
# Automates a guided deployment of the requested instance. The routine builds
# the compose file list (base + instance overrides), executes optional
# validation helpers and, at the end, runs a health check to confirm the state
# after `docker compose up`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/deploy_args.sh
source "$SCRIPT_DIR/lib/deploy_args.sh"

# shellcheck source=lib/deploy_context.sh
source "$SCRIPT_DIR/lib/deploy_context.sh"

# shellcheck source=lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=lib/step_runner.sh
source "$SCRIPT_DIR/lib/step_runner.sh"

if ! eval "$(parse_deploy_args "$@")"; then
  exit 1
fi

if [[ "${DEPLOY_ARGS[SHOW_HELP]}" -eq 1 ]]; then
  print_help
  exit 0
fi

INSTANCE="${DEPLOY_ARGS[INSTANCE]}"
FORCE="${DEPLOY_ARGS[FORCE]}"
DRY_RUN="${DEPLOY_ARGS[DRY_RUN]}"
RUN_STRUCTURE="${DEPLOY_ARGS[RUN_STRUCTURE]}"
RUN_VALIDATE="${DEPLOY_ARGS[RUN_VALIDATE]}"
RUN_HEALTH="${DEPLOY_ARGS[RUN_HEALTH]}"

deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

export COMPOSE_ENV_FILES="${DEPLOY_CONTEXT[COMPOSE_ENV_FILES]}"
export COMPOSE_FILES="${DEPLOY_CONTEXT[COMPOSE_FILES]}"
export LOCAL_INSTANCE="$INSTANCE"
COMPOSE_ROOT_FILE="$REPO_ROOT/docker-compose.yml"

declare -a COMPOSE_CMD=()
if [[ $DRY_RUN -eq 1 ]]; then
  COMPOSE_CMD=(docker compose)
elif ! compose_resolve_command COMPOSE_CMD; then
  exit $?
fi

run_deploy_step() {
  STEP_RUNNER_DRY_RUN="$DRY_RUN" run_step "$@"
}

mapfile -t PERSISTENT_DIRS <<<"${DEPLOY_CONTEXT[PERSISTENT_DIRS]}"
DATA_UID="${DEPLOY_CONTEXT[DATA_UID]}"
DATA_GID="${DEPLOY_CONTEXT[DATA_GID]}"
APP_DATA_UID_GID="${DEPLOY_CONTEXT[APP_DATA_UID_GID]}"
BUILD_COMPOSE_CMD=("$REPO_ROOT/scripts/build_compose_file.sh" "$INSTANCE")
COMPOSE_UP_CMD=("${COMPOSE_CMD[@]}" -f "$COMPOSE_ROOT_FILE" up -d)

compose_env_files_display="${COMPOSE_ENV_FILES//$'\n'/ }"

cat <<SUMMARY_EOF
[*] Instance: $INSTANCE
[*] COMPOSE_ENV_FILES=${compose_env_files_display}
[*] COMPOSE_PLAN=${COMPOSE_FILES}
[*] COMPOSE_ROOT_FILE=${COMPOSE_ROOT_FILE}
SUMMARY_EOF

if [[ $RUN_STRUCTURE -eq 1 ]]; then
  if ! run_deploy_step "Validating repository structure" "$REPO_ROOT/scripts/check_structure.sh"; then
    exit $?
  fi
fi

if [[ $RUN_VALIDATE -eq 1 ]]; then
  if ! run_deploy_step "Validating instance compose manifests" env "COMPOSE_INSTANCES=${INSTANCE}" "$REPO_ROOT/scripts/validate_compose.sh"; then
    exit $?
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[*] Dry-run enabled. No command was executed."
  echo "[*] Planned compose build: $(format_cmd "${BUILD_COMPOSE_CMD[@]}")"
  echo "[*] Planned Docker Compose command: $(format_cmd "${COMPOSE_UP_CMD[@]}")"
  if [[ $RUN_HEALTH -eq 1 ]]; then
    echo "[*] Planned health check: $(format_cmd "$REPO_ROOT/scripts/check_health.sh" "$INSTANCE")"
  else
    echo "[*] Automatic health check skipped (--skip-health flag)."
  fi
  exit 0
fi

if [[ $FORCE -ne 1 && -z "${CI:-}" ]]; then
  read -r -p "Continue with the deployment? [y/N] " answer
  case "$answer" in
  [yY][eE][sS] | [yY]) ;;
  *)
    echo "[!] Execution cancelled by the user." >&2
    exit 1
    ;;
  esac
fi

mkdir -p "${PERSISTENT_DIRS[@]}"

if [[ "$(id -u)" -eq 0 ]]; then
  if chown "$APP_DATA_UID_GID" "${PERSISTENT_DIRS[@]}"; then
    echo "[*] Prepared persistent directories (${PERSISTENT_DIRS[*]}) with owner ${APP_DATA_UID_GID}."
  else
    echo "[!] Warning: failed to set owner ${APP_DATA_UID_GID} on (${PERSISTENT_DIRS[*]}). Continuing with current ownership." >&2
  fi
else
  echo "[*] Prepared persistent directories (${PERSISTENT_DIRS[*]}). Desired owner ${APP_DATA_UID_GID} not applied (insufficient permissions)."
fi

if ! run_deploy_step "Generating docker-compose.yml" "${BUILD_COMPOSE_CMD[@]}"; then
  exit $?
fi

export COMPOSE_FILES="$COMPOSE_ROOT_FILE"

if ! run_deploy_step "Running docker compose (up -d)" "${COMPOSE_UP_CMD[@]}"; then
  exit $?
fi

if [[ $RUN_HEALTH -eq 1 ]]; then
  if ! run_deploy_step "Running post-deploy health check" env COMPOSE_FILES="$COMPOSE_ROOT_FILE" "$REPO_ROOT/scripts/check_health.sh" "$INSTANCE"; then
    exit $?
  fi
else
  echo "[*] Automatic health check skipped (--skip-health flag)."
fi

echo "[*] Guided deployment finished successfully."
