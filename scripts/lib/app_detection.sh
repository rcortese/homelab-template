#!/usr/bin/env bash

# Lista serviços ativos (status running) utilizando o comando docker compose
# informado. O primeiro argumento deve ser o nome de uma variável do tipo array
# (nameref) que receberá o resultado. Os argumentos seguintes representam o
# comando docker compose a ser executado (ex.: docker compose -f docker-compose.yml ...).
app_detection__list_active_services() {
  local __target_ref="$1"
  shift

  if [[ -z "$__target_ref" ]]; then
    echo "[!] app_detection__list_active_services requires a target variable." >&2
    return 1
  fi

  local -n __output_ref=$__target_ref
  __output_ref=()

  if [[ $# -eq 0 ]]; then
    echo "[!] app_detection__list_active_services requer comando docker compose." >&2
    return 1
  fi

  local -a __compose_cmd=("$@")
  local __raw_output=""
  local __status=0

  __raw_output="$("${__compose_cmd[@]}" ps --status running --services 2>/dev/null)" || __status=$?
  if ((__status != 0)); then
    return "${__status}"
  fi

  if [[ -z "$__raw_output" ]]; then
    return 0
  fi

  local __line
  while IFS= read -r __line; do
    [[ -z "$__line" ]] && continue
    __output_ref+=("$__line")
  done <<<"$__raw_output"

  return 0
}
