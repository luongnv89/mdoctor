#!/usr/bin/env bash
#
# fixes/disk.sh
# Free disk space via cleanup + system purge
# Risk: LOW
#

fix_disk() {
  echo "${BOLD}${BLUE}== Freeing Disk Space ==${RESET}"
  echo

  source "${MDOCTOR_DIR}/lib/logging.sh"
  source "${MDOCTOR_DIR}/lib/disk.sh"

  # shellcheck disable=SC2034
  DRY_RUN=false
  LOGFILE="${HOME}/Library/Logs/macos_cleanup.log"
  # shellcheck disable=SC2034
  DAYS_OLD="${DAYS_OLD_OVERRIDE:-7}"

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
  sudo purge 2>/dev/null || true

  local used_after_kb
  used_after_kb="$(disk_used_kb)"
  local freed_kb=$((used_before_kb - used_after_kb))
  if ((freed_kb < 0)); then freed_kb=0; fi

  echo
  echo "${GREEN}Disk cleanup complete. Freed approximately $(human_readable_kb "$freed_kb").${RESET}"
}
