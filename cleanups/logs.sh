#!/usr/bin/env bash
#
# cleanups/logs.sh
# Old logs cleanup
#

clean_logs() {
  local days="${DAYS_OLD:-7}"
  local log_dir
  log_dir="$(platform_user_log_dir)"
  header "Cleaning user logs older than ${days} days (${log_dir})"
  if [ -d "$log_dir" ]; then
    safe_find_delete "$log_dir" -type f -mtime "+${days}" || true
  else
    log "No log directory found at ${log_dir}."
  fi
}
