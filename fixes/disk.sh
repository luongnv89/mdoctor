#!/usr/bin/env bash
#
# fixes/disk.sh
# Free disk space via cleanup + system purge
# Risk: LOW
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required fixes inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
fix_disk() {
  header "Freeing Disk Space"

  # Task 1.3: every step below is macOS-shaped (purge, macOS log layout).
  # Refuse on Linux instead of printing progress for work that never
  # happens; the dispatch gate (Task 1.2) rejects earlier with the same
  # message when reached via `mdoctor fix disk`.
  if ! is_macos; then
    echo "${YELLOW}Disk fix is macOS-only — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  source "${MDOCTOR_DIR}/lib/logging.sh"
  source "${MDOCTOR_DIR}/lib/disk.sh"

  # Task 4.4: no local DRY_RUN override — the ambient mode (force by
  # default under `mdoctor fix`, dry-run with DRY_RUN=true) flows into
  # the cleanup helpers and run_cmd_args alike.
  LOGFILE="$(platform_log_dir)/mdoctor_cleanup.log"

  mkdir -p "$(dirname "$LOGFILE")"

  local used_before_kb
  used_before_kb="$(disk_used_kb)"

  echo "${CYAN}[1/4]${RESET} Emptying Trash..."
  source "${MDOCTOR_DIR}/cleanups/trash.sh"
  clean_trash

  echo "${CYAN}[2/4]${RESET} Cleaning user caches..."
  source "${MDOCTOR_DIR}/cleanups/caches.sh"
  clean_user_caches

  echo "${CYAN}[3/4]${RESET} Cleaning old logs..."
  source "${MDOCTOR_DIR}/cleanups/logs.sh"
  clean_logs

  echo "${CYAN}[4/4]${RESET} Purging system caches..."
  local step_rc=0
  run_cmd_args sudo purge 2>/dev/null || step_rc=$?

  local used_after_kb
  used_after_kb="$(disk_used_kb)"
  local freed_kb=$((used_before_kb - used_after_kb))
  if ((freed_kb < 0)); then
    freed_kb=0
  fi

  echo
  if [ "$step_rc" -eq 0 ]; then
    status_ok "Disk cleanup complete. Freed approximately $(human_readable_kb "$freed_kb")."
    return 0
  else
    status_warn "Disk cleanup finished with errors (purge failed)."
    return 1
  fi
}
