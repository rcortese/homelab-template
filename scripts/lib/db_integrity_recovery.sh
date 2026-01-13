#!/usr/bin/env bash

RECOVERY_BACKUP_PATH=""
RECOVERY_DETAILS=""

attempt_recovery() {
  local db_file="$1"
  local tmp_dir

  RECOVERY_BACKUP_PATH=""
  RECOVERY_DETAILS=""

  if ! tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/db-recovery.XXXXXX")"; then
    RECOVERY_DETAILS="failed to create temporary directory"
    return 1
  fi

  local dump_file="$tmp_dir/recover.sql"
  local log_file="$tmp_dir/recover.log"
  local new_db="$tmp_dir/recovered.db"
  local timestamp backup_file

  if ! sqlite3_exec "$db_file" ".recover" >"$dump_file" 2>"$log_file"; then
    RECOVERY_DETAILS="sqlite3 .recover failed: $(tr '\n' ' ' <"$log_file")"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! sqlite3_exec "$new_db" <"$dump_file" 2>>"$log_file"; then
    RECOVERY_DETAILS="failed to recreate database: $(tr '\n' ' ' <"$log_file")"
    rm -rf "$tmp_dir"
    return 1
  fi

  timestamp="$(date +%Y%m%d%H%M%S)"
  backup_file="${db_file}.${timestamp}.bak"

  if ! cp -p "$db_file" "$backup_file"; then
    RECOVERY_DETAILS="failed to save original backup to $backup_file"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$new_db" "$db_file"; then
    RECOVERY_DETAILS="failed to replace corrupted database"
    cp -p "$backup_file" "$db_file" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
    return 1
  fi

  RECOVERY_BACKUP_PATH="$backup_file"
  if [[ -s "$log_file" ]]; then
    RECOVERY_DETAILS="recovery completed with notes: $(tr '\n' ' ' <"$log_file")"
  else
    RECOVERY_DETAILS="recovery completed via sqlite3 .recover"
  fi

  rm -rf "$tmp_dir"
  return 0
}
