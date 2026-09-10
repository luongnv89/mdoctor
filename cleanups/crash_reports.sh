#!/usr/bin/env bash
#
# cleanups/crash_reports.sh
# Remove old crash/diagnostic reports
# Risk: LOW
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_crash_reports() {
  local days="${DAYS_OLD:-30}"
  header "Cleaning crash reports older than ${days} days"

  local dir
  while IFS= read -r dir; do
    if [ ! -d "$dir" ]; then
      log "Directory not found: ${dir} — skipping."
      continue
    fi

    # System-wide report dirs (e.g. /Library/Logs/DiagnosticReports) are
    # outside the allowed deletion roots (Task 0.4) — skip with a reason
    # instead of attempting deletion.
    if ! validate_deletion_path "$dir" >/dev/null 2>&1; then
      log "Skipping out-of-scope directory: ${dir} — outside the allowed deletion roots."
      continue
    fi

    log "Scanning ${dir} for .crash, .diag, .ips files older than ${days} days..."
    safe_find_delete "$dir" -type f "(" -name "*.crash" -o -name "*.diag" -o -name "*.ips" ")" -mtime "+${days}" || true
  done < <(platform_crash_dirs)
}
