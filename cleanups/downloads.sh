#!/usr/bin/env bash
#
# cleanups/downloads.sh
# Large files in Downloads
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
clean_downloads_large_files() {
  local rc=0
  local days="${DAYS_OLD:-7}"
  header "Listing large files in Downloads (>500MB, older than ${days} days)"
  if [ -d "${HOME}/Downloads" ]; then
    # Only list by default; you can uncomment the delete line if you want.
    run_cmd_args find "${HOME}/Downloads" -type f -size +500M -mtime "+${days}" -print || rc=$?
    # To actually delete matching files in future, use:
    # safe_find_delete "${HOME}/Downloads" -type f -size +500M -mtime "+${days}"
  else
    log "No ~/Downloads directory found."
  fi
  [ "$rc" -eq 0 ] || log "Module 'downloads' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'downloads')"
  return "$rc"
}
