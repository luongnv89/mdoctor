#!/usr/bin/env bash
#
# cleanups/logs.sh
# Old logs cleanup
#

clean_logs() {
  local days="${DAYS_OLD:-7}"
  header "Cleaning user logs older than ${days} days (~/Library/Logs)"
  if [ -d "${HOME}/Library/Logs" ]; then
    safe_find_delete "${HOME}/Library/Logs" -type f -mtime "+${days}" || true
  else
    log "No ~/Library/Logs directory found."
  fi
}
