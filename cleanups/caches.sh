#!/usr/bin/env bash
#
# cleanups/caches.sh
# User caches cleanup
#

clean_user_caches() {
  local cache_dir
  cache_dir="$(platform_cache_dir)"
  header "Cleaning user caches (${cache_dir})"
  if [ -d "$cache_dir" ]; then
    safe_remove_children "$cache_dir" || true
  else
    log "No cache directory found at ${cache_dir}."
  fi
}
