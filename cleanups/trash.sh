#!/usr/bin/env bash
#
# cleanups/trash.sh
# Empty Trash
#

clean_trash() {
  header "Emptying Trash (~/.Trash)"
  if [ -d "${HOME}/.Trash" ]; then
    safe_remove_children "${HOME}/.Trash" || true
  else
    log "Trash folder not found."
  fi
}
