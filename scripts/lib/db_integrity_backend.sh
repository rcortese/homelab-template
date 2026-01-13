#!/usr/bin/env bash

resolve_sqlite_backend() {
  local resolved_bin=""

  case "$SQLITE3_MODE" in
  binary)
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Error: sqlite3 not found (binary: $SQLITE3_BIN)." >&2
    exit 127
    ;;
  container)
    if command -v "$SQLITE3_CONTAINER_RUNTIME" >/dev/null 2>&1; then
      SQLITE3_BACKEND="container"
      SQLITE3_BIN_PATH=""
      return 0
    fi
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      echo "[!] Runtime '$SQLITE3_CONTAINER_RUNTIME' unavailable; using binary '$resolved_bin'." >&2
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Error: runtime '$SQLITE3_CONTAINER_RUNTIME' unavailable and sqlite3 (binary: $SQLITE3_BIN) missing." >&2
    exit 127
    ;;
  auto | *)
    if command -v "$SQLITE3_CONTAINER_RUNTIME" >/dev/null 2>&1; then
      SQLITE3_BACKEND="container"
      SQLITE3_BIN_PATH=""
      return 0
    fi
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Error: sqlite3 not found and runtime '$SQLITE3_CONTAINER_RUNTIME' unavailable." >&2
    exit 127
    ;;
  esac
}

sqlite3_exec() {
  if [[ "$SQLITE3_BACKEND" == "binary" ]]; then
    "$SQLITE3_BIN_PATH" "$@"
    return $?
  fi

  declare -a volume_args=()
  declare -A mounted_paths=()
  local arg path dir

  for arg in "$@"; do
    if [[ "$arg" == /* ]]; then
      path="$arg"
      if [[ -d "$path" ]]; then
        dir="$path"
      else
        dir="$(dirname "$path")"
      fi

      if [[ -n "$dir" && -d "$dir" && -z "${mounted_paths[$dir]:-}" ]]; then
        volume_args+=("--volume" "$dir:$dir:rw")
        mounted_paths[$dir]=1
      fi
    fi
  done

  if [[ -d "$REPO_ROOT" && -z "${mounted_paths[$REPO_ROOT]:-}" ]]; then
    volume_args+=("--volume" "$REPO_ROOT:$REPO_ROOT:rw")
    mounted_paths[$REPO_ROOT]=1
  fi

  local workdir="$REPO_ROOT"
  if [[ ! -d "$workdir" ]]; then
    workdir="$PWD"
  fi

  "$SQLITE3_CONTAINER_RUNTIME" run --rm -i \
    "${volume_args[@]}" \
    --workdir "$workdir" \
    "$SQLITE3_CONTAINER_IMAGE" \
    sqlite3 "$@"
}
