#!/usr/bin/env bash

# Utility helpers for working with docker compose file references.

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
