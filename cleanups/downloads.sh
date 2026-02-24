#!/usr/bin/env bash
#
# cleanups/downloads.sh
# Large files in Downloads
#

clean_downloads_large_files() {
  local days="${DAYS_OLD:-7}"
  header "Listing large files in Downloads (>500MB, older than ${days} days)"
  if [ -d "${HOME}/Downloads" ]; then
    # Only list by default; you can uncomment the delete line if you want.
    run_cmd_args find "${HOME}/Downloads" -type f -size +500M -mtime "+${days}" -print
    # To actually delete matching files in future, use:
    # safe_find_delete "${HOME}/Downloads" -type f -size +500M -mtime "+${days}"
  else
    log "No ~/Downloads directory found."
  fi
}
