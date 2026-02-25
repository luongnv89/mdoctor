#!/usr/bin/env bash
#
# cleanups/trash.sh
# Empty Trash
#

clean_trash() {
  local trash_dir
  trash_dir="$(platform_trash_dir)"
  header "Emptying Trash (${trash_dir})"
  if [ -d "$trash_dir" ]; then
    safe_remove_children "$trash_dir" || true
  else
    log "Trash folder not found."
  fi
}
