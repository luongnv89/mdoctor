#!/usr/bin/env bash
#
# cleanups/logs.sh
# Old logs cleanup
#

clean_logs() {
  local days="${DAYS_OLD:-7}"
  header "Cleaning user logs older than ${days} days (~/Library/Logs)"
  if [ -d "${HOME}/Library/Logs" ]; then
    run_cmd "find \"${HOME}/Library/Logs\" -type f -mtime +${days} -print -delete"
  else
    log "No ~/Library/Logs directory found."
  fi
}
