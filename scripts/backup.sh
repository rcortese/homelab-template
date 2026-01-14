#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/backup.sh <instance>
#
# Runs a simple backup by stopping the related stack, copying persisted data
# to the `backups/` directory, and restarting the stack at the end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  cat <<'USAGE' >&2
Usage: scripts/backup.sh <instance>

Stops the stack for the given instance, copies persisted data into a snapshot
in backups/<instance>-<timestamp>, then starts the services again.
USAGE
  exit 1
fi

INSTANCE="$1"

# shellcheck source=_internal/lib/deploy_context.sh
source "$SCRIPT_DIR/_internal/lib/deploy_context.sh"

# shellcheck source=_internal/lib/app_detection.sh
source "$SCRIPT_DIR/_internal/lib/app_detection.sh"

# shellcheck source=_internal/lib/compose_command.sh
source "$SCRIPT_DIR/_internal/lib/compose_command.sh"

deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

export COMPOSE_ENV_FILES="${DEPLOY_CONTEXT[COMPOSE_ENV_FILES]}"
export COMPOSE_FILES="${DEPLOY_CONTEXT[COMPOSE_FILES]}"
export LOCAL_INSTANCE="$INSTANCE"
COMPOSE_ROOT_FILE="$REPO_ROOT/docker-compose.yml"

declare -a DOCKER_COMPOSE_CMD=()
if ! compose_resolve_command DOCKER_COMPOSE_CMD; then
  exit $?
fi

BUILD_COMPOSE_CMD=("$REPO_ROOT/scripts/build_compose_file.sh" "$INSTANCE")
COMPOSE_CMD=("${DOCKER_COMPOSE_CMD[@]}" -f "$COMPOSE_ROOT_FILE")

stack_was_stopped=0
restart_failed=0
declare -a ACTIVE_APP_SERVICES=()
declare -a KNOWN_APP_NAMES=()

if [[ -n "${DEPLOY_CONTEXT[APP_NAMES]:-}" ]]; then
  mapfile -t KNOWN_APP_NAMES < <(printf '%s\n' "${DEPLOY_CONTEXT[APP_NAMES]}")
fi

if ! "${BUILD_COMPOSE_CMD[@]}"; then
  echo "[!] Failed to generate docker-compose.yml before the backup." >&2
  exit 1
fi

export COMPOSE_FILES="$COMPOSE_ROOT_FILE"

if ! app_detection__list_active_services ACTIVE_APP_SERVICES "${COMPOSE_CMD[@]}"; then
  echo "[!] Unable to list active services before the backup." >&2
  ACTIVE_APP_SERVICES=()
fi

if ((${#KNOWN_APP_NAMES[@]} > 0)) && ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
  declare -a ORDERED_ACTIVE_APPS=()
  declare -A ORDERED_ACTIVE_SEEN=()

  for known_app in "${KNOWN_APP_NAMES[@]}"; do
    for detected_app in "${ACTIVE_APP_SERVICES[@]}"; do
      if [[ "$detected_app" == "$known_app" && -z "${ORDERED_ACTIVE_SEEN[$detected_app]:-}" ]]; then
        ORDERED_ACTIVE_APPS+=("$detected_app")
        ORDERED_ACTIVE_SEEN["$detected_app"]=1
        break
      fi
    done
  done

  for detected_app in "${ACTIVE_APP_SERVICES[@]}"; do
    if [[ -z "${ORDERED_ACTIVE_SEEN[$detected_app]:-}" ]]; then
      ORDERED_ACTIVE_APPS+=("$detected_app")
      ORDERED_ACTIVE_SEEN["$detected_app"]=1
    fi
  done

  ACTIVE_APP_SERVICES=("${ORDERED_ACTIVE_APPS[@]}")
fi

restart_stack() {
  local restart_status=0
  if [[ $stack_was_stopped -eq 1 ]]; then
    if ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
      if "${COMPOSE_CMD[@]}" up -d "${ACTIVE_APP_SERVICES[@]}"; then
        echo "[*] Applications '${ACTIVE_APP_SERVICES[*]}' restarted."
      else
        echo "[!] Failed to restart applications '${ACTIVE_APP_SERVICES[*]}' for instance '$INSTANCE'. Please check manually." >&2
        restart_failed=1
        restart_status=1
      fi
    else
      echo "[*] No services will be restarted; none were active at the start of the backup."
    fi
    stack_was_stopped=0
  fi
  return $restart_status
}
trap restart_stack EXIT

echo "[*] Stopping stack '$INSTANCE' before the backup..."
if "${COMPOSE_CMD[@]}" down; then
  stack_was_stopped=1
else
  echo "[!] Failed to stop stack '$INSTANCE'." >&2
  exit 1
fi

app_data_dir_rel="${DEPLOY_CONTEXT[APP_DATA_REL]}"
app_data_path="${DEPLOY_CONTEXT[APP_DATA_PATH]}"

echo "[*] Data directory (relative): ${app_data_dir_rel:-<not configured>}"

if [[ -z "$app_data_path" ]]; then
  echo "[!] Data directory not identified for instance '$INSTANCE'." >&2
  exit 1
fi

data_src="$app_data_path"

if [[ ! -d "$data_src" ]]; then
  echo "[!] Data directory '$data_src' does not exist." >&2
  exit 1
fi

if ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
  echo "[*] Applications detected to restart: ${ACTIVE_APP_SERVICES[*]}"
else
  echo "[*] No active applications detected; no services will be restarted."
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$REPO_ROOT/backups/${INSTANCE}-${timestamp}"
mkdir -p "$backup_dir"

echo "[*] Copying data from '$data_src' to '$backup_dir'..."
if ! cp -a "$data_src/." "$backup_dir/"; then
  rm -rf "$backup_dir"
  echo "[!] Failed to copy data to '$backup_dir'." >&2
  exit 1
fi

echo "[*] Backup for instance '$INSTANCE' completed at '$backup_dir'."

# Restart the stack (trap handles it on earlier errors).
restart_stack || true
trap - EXIT

if [[ $restart_failed -eq 1 ]]; then
  exit 1
fi

echo "[*] Process finished successfully."
