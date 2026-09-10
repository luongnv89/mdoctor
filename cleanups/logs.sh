#!/usr/bin/env bash
#
# cleanups/logs.sh
# Old logs cleanup
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
clean_logs() {
  local days="${DAYS_OLD:-7}"
  local log_dir
  log_dir="$(platform_user_log_dir)"
  header "Cleaning user logs older than ${days} days (${log_dir})"
  if [ -d "$log_dir" ]; then
    safe_find_delete "$log_dir" -type f -mtime "+${days}" || true
  else
    log "No log directory found at ${log_dir}."
  fi
}
