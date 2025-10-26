#!/usr/bin/env bash

require_interactive_input() {
  local message="$1"
  if [[ ! -t 0 ]]; then
    error "$message"
  fi
}

prompt_required_value() {
  local prompt_message="$1"
  local value=""
  while true; do
    read -r -p "$prompt_message: " value
    if [[ -n "${value// /}" ]]; then
      printf '%s' "$value"
      return 0
    fi
    printf '%s\n' "Valor obrigatório. Tente novamente." >&2
  done
}

prompt_value_with_default() {
  local prompt_message="$1"
  local default_value="$2"
  local value=""
  read -r -p "$prompt_message [$default_value]: " value
  if [[ -n "${value// /}" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}
