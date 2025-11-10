#!/usr/bin/env bash

print_help() {
  cat <<'USAGE'
Usage: scripts/deploy_instance.sh <instance> [flags]

Runs a guided deployment for the requested instance (core/media). The command
automatically assembles the compose files (base + instance overrides) and
executes optional validation helpers.

Positional arguments:
  instance        Name of the instance (for example: core, media).

Flags:
  --dry-run         Only display the commands that would be executed.
  --force           Skip interactive confirmations (handy locally or in CI).
  --skip-structure  Skip scripts/check_structure.sh before the deployment.
  --skip-validate   Skip scripts/validate_compose.sh before the deployment.
  --skip-health     Skip scripts/check_health.sh after the deployment.
  -h, --help        Show this help message and exit.

Relevant environment variables:
  CI                When set, assume non-interactive mode (same as --force).
USAGE
}

parse_deploy_args() {
  local instance=""
  local force=0
  local dry_run=0
  local run_structure=1
  local run_validate=1
  local run_health=1
  local show_help=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      show_help=1
      shift
      continue
      ;;
    --force)
      force=1
      shift
      continue
      ;;
    --dry-run)
      dry_run=1
      shift
      continue
      ;;
    --skip-structure)
      run_structure=0
      shift
      continue
      ;;
    --skip-validate)
      run_validate=0
      shift
      continue
      ;;
    --skip-health)
      run_health=0
      shift
      continue
      ;;
    -*)
      echo "[!] Unknown flag: $1" >&2
      echo >&2
      print_help >&2
      return 1
      ;;
    *)
      if [[ -z "$instance" ]]; then
        instance="$1"
        shift
        continue
      fi
      echo "[!] Unexpected parameter: $1" >&2
      echo >&2
      print_help >&2
      return 1
      ;;
    esac
  done

  if [[ $show_help -eq 0 && -z "$instance" ]]; then
    echo "[!] Instance not provided." >&2
    echo >&2
    print_help >&2
    return 1
  fi

  printf 'declare -A DEPLOY_ARGS=(\n'
  printf '  [INSTANCE]=%q\n' "$instance"
  printf '  [FORCE]=%q\n' "$force"
  printf '  [DRY_RUN]=%q\n' "$dry_run"
  printf '  [RUN_STRUCTURE]=%q\n' "$run_structure"
  printf '  [RUN_VALIDATE]=%q\n' "$run_validate"
  printf '  [RUN_HEALTH]=%q\n' "$run_health"
  printf '  [SHOW_HELP]=%q\n' "$show_help"
  printf ')\n'
}
