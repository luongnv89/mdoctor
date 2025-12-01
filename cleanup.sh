#!/usr/bin/env bash
#
# cleanup.sh
# Generic manual cleanup script for macOS with progress + summary.
#
# Default: DRY RUN (shows what would be deleted, nothing actually removed).
# Usage:
#   ./cleanup.sh           # dry run
#   ./cleanup.sh --force   # actually delete
#

set -euo pipefail

########################################
# SCRIPT DIRECTORY & MODULE LOADING
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/disk.sh"

# Source cleanup modules
source "${SCRIPT_DIR}/cleanups/trash.sh"
source "${SCRIPT_DIR}/cleanups/caches.sh"
source "${SCRIPT_DIR}/cleanups/logs.sh"
source "${SCRIPT_DIR}/cleanups/downloads.sh"
source "${SCRIPT_DIR}/cleanups/browser.sh"
source "${SCRIPT_DIR}/cleanups/dev.sh"

########################################
# CONFIGURATION
########################################

DRY_RUN=true
LOGFILE="${HOME}/Library/Logs/macos_cleanup.log"
DAYS_OLD=7   # logs / old files older than this will be considered

# If --force is passed, disable dry-run
if [[ "${1-}" == "--force" ]]; then
  DRY_RUN=false
fi

########################################
# PROGRESS HANDLING
########################################

PROGRESS_CURRENT=0
PROGRESS_TOTAL=4   # update if you add/remove core steps below

step() {
  PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
  local label="$1"
  echo
  echo "➤ [${PROGRESS_CURRENT}/${PROGRESS_TOTAL}] ${label}"
}

########################################
# MAIN
########################################

main() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo >> "$LOGFILE"

  local used_before_kb
  local used_after_kb
  local freed_kb
  local freed_hr

  used_before_kb="$(disk_used_kb)"

  header "Starting macOS cleanup (DRY_RUN=${DRY_RUN})"
  log "$(disk_usage)"

  # Core generic cleanups – safe-ish for any macOS user
  step "Emptying Trash"
  clean_trash

  step "Cleaning user caches"
  clean_user_caches

  step "Cleaning old logs"
  clean_logs

  step "Scanning large files in Downloads"
  clean_downloads_large_files

  # OPTIONAL: Uncomment if you want these too (and bump PROGRESS_TOTAL)
  # step "Cleaning browser caches"
  # clean_browser_caches
  #
  # step "Developer caches & tools cleanup"
  # clean_dev_stuff

  if [ "$DRY_RUN" = true ]; then
    used_after_kb="$used_before_kb"
  else
    used_after_kb="$(disk_used_kb)"
  fi

  freed_kb=$((used_before_kb - used_after_kb))
  if (( freed_kb < 0 )); then
    freed_kb=0
  fi

  freed_hr="$(human_readable_kb "$freed_kb")"

  log "Cleanup finished."
  log "$(disk_usage)"

  if [ "$DRY_RUN" = true ]; then
    log "Estimated space that COULD be freed: ${freed_hr} (dry run – no actual changes made)."
  else
    log "Estimated space freed: ${freed_hr}."
  fi
}

main "$@"
