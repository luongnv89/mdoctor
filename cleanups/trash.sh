#!/usr/bin/env bash
#
# cleanups/trash.sh
# Empty Trash
#

clean_trash() {
  header "Emptying Trash (~/.Trash)"
  if [ -d "${HOME}/.Trash" ]; then
    run_cmd "rm -rf \"${HOME}/.Trash\"/*"
  else
    log "Trash folder not found."
  fi
}
