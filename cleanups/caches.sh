#!/usr/bin/env bash
#
# cleanups/caches.sh
# User caches cleanup
#

clean_user_caches() {
  header "Cleaning user caches (~/Library/Caches)"
  if [ -d "${HOME}/Library/Caches" ]; then
    safe_remove_children "${HOME}/Library/Caches" || true
  else
    log "No ~/Library/Caches directory found."
  fi
}
