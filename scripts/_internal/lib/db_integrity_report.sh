#!/usr/bin/env bash

record_result() {
  local path="$1"
  local status="$2"
  local message="$3"
  local action="$4"
  DB_RESULTS+=("${path}${FIELD_SEPARATOR}${status}${FIELD_SEPARATOR}${message}${FIELD_SEPARATOR}${action}")
}

json_escape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "$raw"
}

generate_json_report() {
  local first=1
  printf '{"format":"json","overall_status":%d,"databases":[' "$overall_status"
  for entry in "${DB_RESULTS[@]}"; do
    IFS="$FIELD_SEPARATOR" read -r path status message action <<<"$entry"
    if ((first)); then
      first=0
    else
      printf ','
    fi
    printf '{"path":"%s","status":"%s","message":"%s","action":"%s"}' \
      "$(json_escape "$path")" \
      "$(json_escape "$status")" \
      "$(json_escape "$message")" \
      "$(json_escape "$action")"
  done
  printf ']'
  printf ',"alerts":['
  first=1
  for alert in "${ALERTS[@]}"; do
    if ((first)); then
      first=0
    else
      printf ','
    fi
    printf '"%s"' "$(json_escape "$alert")"
  done
  printf ']}'
}

generate_text_report() {
  local lines=()
  lines+=("SQLite database integrity summary:")
  for entry in "${DB_RESULTS[@]}"; do
    IFS="$FIELD_SEPARATOR" read -r path status message action <<<"$entry"
    lines+=("Database: $path")
    lines+=("  status: $status")
    lines+=("  message: $message")
    lines+=("  action: $action")
  done
  if ((${#ALERTS[@]} > 0)); then
    lines+=("Alerts:")
    for alert in "${ALERTS[@]}"; do
      lines+=("- $alert")
    done
  fi
  printf '%s\n' "${lines[@]}"
}
