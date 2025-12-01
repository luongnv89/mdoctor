#!/usr/bin/env bash
#
# cleanups/caches.sh
# User caches cleanup
#

clean_user_caches() {
  header "Cleaning user caches (~/Library/Caches)"
  if [ -d "${HOME}/Library/Caches" ]; then
    # Remove only direct children to avoid weird behavior with symlinks, etc.
    run_cmd "find \"${HOME}/Library/Caches\" -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  else
    log "No ~/Library/Caches directory found."
  fi
}
