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
  header "Listing large files in Downloads (>500MB, older than ${days} days) — report only"
  # Issue #112: report-only by design. The deletion was never enabled (the
  # safe_find_delete call was commented out since import) and ~/Downloads
  # is outside the allowed deletion roots in lib/safety.sh, so this module
  # only ever lists matches. It is registered SAFE, runs no destructive
  # pre-flight, and is excluded from the engine's PROGRESS_TOTAL. The
  # find runs directly (not via dry-run-gated run_cmd_args) so the report
  # is produced in every mode.
  if [ -d "${HOME}/Downloads" ]; then
    find "${HOME}/Downloads" -type f -size +500M -mtime "+${days}" -print 2>/dev/null || rc=$?
  else
    log "No ~/Downloads directory found."
  fi
  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'downloads' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'downloads')"
  return "$rc"
}
