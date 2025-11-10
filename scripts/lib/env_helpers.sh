#!/usr/bin/env bash
# Common helpers for environment variable handling in scripts.

_ENV_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_env_pairs() {
  local env_file="$1"
  shift || return 0

  if [[ ! -f "$env_file" ]]; then
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    return 2
  fi

  local output=""
  if ! output="$("${_ENV_HELPERS_DIR}/env_loader.sh" "$env_file" "$@")"; then
    return $?
  fi

  local line key value
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    key="${line%%=*}"
    if [[ -z "$key" ]]; then
      continue
    fi
    if [[ -n "${!key+x}" ]]; then
      continue
    fi
    value="${line#*=}"
    export "$key=$value"
  done <<<"$output"

  return 0
}

env_helpers__normalize_repo_relative() {
  local repo_root="$1"
  local input_value="${2:-}"

  if [[ -z "$input_value" ]]; then
    printf '%s' ""
    return 0
  fi

  python3 - "$repo_root" "$input_value" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
raw = sys.argv[2]

candidate = Path(raw)
if candidate.is_absolute():
    absolute = candidate
else:
    absolute = (root / candidate)

absolute = absolute.resolve(strict=False)

try:
    relative = absolute.relative_to(root)
except ValueError:
    sys.stderr.write(
        f"[!] Path outside the repository: {absolute.as_posix()}\n"
    )
    sys.exit(1)

relative_text = relative.as_posix()
if relative_text == '.':
    relative_text = ''

sys.stdout.write(relative_text)
PY
}

env_helpers__normalize_absolute_path() {
  local repo_root="$1"
  local input_value="${2:-}"

  if [[ -z "$input_value" ]]; then
    printf '%s' ""
    return 0
  fi

  python3 - "$repo_root" "$input_value" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
raw = sys.argv[2]

candidate = Path(raw)
if candidate.is_absolute():
    absolute = candidate
else:
    absolute = root / candidate

absolute = absolute.resolve(strict=False)

sys.stdout.write(absolute.as_posix())
PY
}

env_helpers__relative_from_absolute() {
  local repo_root="$1"
  local absolute_value="$2"

  if [[ -z "$absolute_value" ]]; then
    return 1
  fi

  python3 - "$repo_root" "$absolute_value" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
absolute = Path(sys.argv[2]).resolve(strict=False)

try:
    relative = absolute.relative_to(root)
except ValueError:
    sys.exit(1)

relative_text = relative.as_posix()
if relative_text == '.':
    relative_text = ''

sys.stdout.write(relative_text)
PY
}

env_helpers__derive_app_data_paths() {
  local repo_root="$1"
  local service_slug="$2"
  local default_rel_input="${3:-}"
  local app_data_dir_input="${4:-}"
  local app_data_dir_mount_input="${5:-}"
  local -n __app_data_dir_out=$6
  local -n __app_data_dir_mount_out=$7

  if [[ -n "$app_data_dir_input" && -n "$app_data_dir_mount_input" ]]; then
    echo "Error: APP_DATA_DIR and APP_DATA_DIR_MOUNT cannot be defined at the same time." >&2
    return 1
  fi

  local default_rel=""
  if [[ -n "$default_rel_input" ]]; then
    if ! default_rel="$(env_helpers__normalize_repo_relative "$repo_root" "$default_rel_input")"; then
      echo "Error: invalid default APP_DATA_DIR path: $default_rel_input" >&2
      return 1
    fi
  fi

  local normalized_rel=""
  local derived_mount=""

  if [[ -n "$app_data_dir_mount_input" ]]; then
    if ! derived_mount="$(env_helpers__normalize_absolute_path "$repo_root" "$app_data_dir_mount_input")"; then
      echo "Error: unable to normalize APP_DATA_DIR_MOUNT '${app_data_dir_mount_input}'." >&2
      return 1
    fi

    derived_mount="${derived_mount%/}"

    local mount_base="$derived_mount"
    if [[ -n "$service_slug" ]]; then
      local mount_last_component="${derived_mount##*/}"
      if [[ "$mount_last_component" != "$service_slug" ]]; then
        derived_mount="${derived_mount}/${service_slug}"
        mount_base="${derived_mount%/*}"
      else
        mount_base="${derived_mount%/*}"
      fi
    fi

    local rel_candidate=""
    if rel_candidate="$(env_helpers__relative_from_absolute "$repo_root" "$mount_base")"; then
      normalized_rel="$rel_candidate"
    else
      normalized_rel="$default_rel"
    fi
  else
    if [[ -n "$app_data_dir_input" ]]; then
      if ! normalized_rel="$(env_helpers__normalize_repo_relative "$repo_root" "$app_data_dir_input")"; then
        echo "Error: invalid APP_DATA_DIR value: $app_data_dir_input" >&2
        return 1
      fi
    else
      normalized_rel="$default_rel"
    fi

    if [[ -n "$normalized_rel" ]]; then
      local absolute_base=""
      if ! absolute_base="$(env_helpers__normalize_absolute_path "$repo_root" "$normalized_rel")"; then
        echo "Error: unable to compute absolute path for '$normalized_rel'." >&2
        return 1
      fi
      absolute_base="${absolute_base%/}"
      if [[ -n "$service_slug" ]]; then
        if [[ "$absolute_base" == */"$service_slug" ]]; then
          derived_mount="$absolute_base"
        else
          derived_mount="${absolute_base}/${service_slug}"
        fi
      else
        derived_mount="$absolute_base"
      fi
    else
      derived_mount=""
    fi
  fi

  if [[ -z "$derived_mount" ]]; then
    echo "Error: unable to derive APP_DATA_DIR_MOUNT." >&2
    return 1
  fi

  __app_data_dir_out="$normalized_rel"
  __app_data_dir_mount_out="$derived_mount"
  return 0
}
