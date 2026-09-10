#!/usr/bin/env bash
#
# cleanups/caches.sh
# User caches cleanup
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_user_caches() {
  local rc=0
  local cache_dir
  cache_dir="$(platform_cache_dir)"
  header "Cleaning user caches (${cache_dir})"
  if [ -d "$cache_dir" ]; then
    safe_remove_children "$cache_dir" || rc=$?
  else
    log "No cache directory found at ${cache_dir}."
  fi
  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'caches' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'caches')"
  return "$rc"
}
