#!/usr/bin/env bash
#
# macos_cleanup.sh
# Generic manual cleanup script for macOS with progress + summary.
#
# Default: DRY RUN (shows what would be deleted, nothing actually removed).
# Usage:
#   ./macos_cleanup.sh           # dry run
#   ./macos_cleanup.sh --force   # actually delete
#

set -euo pipefail

DRY_RUN=true
LOGFILE="${HOME}/Library/Logs/macos_cleanup.log"
DAYS_OLD=7   # logs / old files older than this will be considered

# If --force is passed, disable dry-run
if [[ "${1-}" == "--force" ]]; then
  DRY_RUN=false
fi

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*" | tee -a "$LOGFILE"
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] $*"
  else
    log "[RUN] $*"
    eval "$@"
  fi
}

header() {
  echo
  log "========== $* =========="
}

disk_usage() {
  df -h / | awk 'NR==2 {print "Disk usage: "$3" used / "$2" total ("$5" used)"}'
}

disk_used_kb() {
  # Used space for / in KB
  df -k / | awk 'NR==2 {print $3}'
}

human_readable_kb() {
  local kb="$1"

  if (( kb < 0 )); then
    kb=$(( -kb ))
  fi

  if (( kb >= 1048576 )); then
    # >= 1 GB
    awk -v kb="$kb" 'BEGIN {printf "%.2f GB", kb/1048576}'
  elif (( kb >= 1024 )); then
    # >= 1 MB
    awk -v kb="$kb" 'BEGIN {printf "%.2f MB", kb/1024}'
  else
    printf "%d KB" "$kb"
  fi
}

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
# CORE GENERIC CLEANUPS (SAFE-ISH)
########################################

clean_trash() {
  header "Emptying Trash (~/.Trash)"
  if [ -d "${HOME}/.Trash" ]; then
    run_cmd "rm -rf \"${HOME}/.Trash\"/*"
  else
    log "Trash folder not found."
  fi
}

clean_user_caches() {
  header "Cleaning user caches (~/Library/Caches)"
  if [ -d "${HOME}/Library/Caches" ]; then
    # Remove only direct children to avoid weird behavior with symlinks, etc.
    run_cmd "find \"${HOME}/Library/Caches\" -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  else
    log "No ~/Library/Caches directory found."
  fi
}

clean_logs() {
  header "Cleaning user logs older than ${DAYS_OLD} days (~/Library/Logs)"
  if [ -d "${HOME}/Library/Logs" ]; then
    run_cmd "find \"${HOME}/Library/Logs\" -type f -mtime +${DAYS_OLD} -print -delete"
  else
    log "No ~/Library/Logs directory found."
  fi
}

clean_downloads_large_files() {
  header "Listing large files in Downloads (>500MB, older than ${DAYS_OLD} days)"
  if [ -d "${HOME}/Downloads" ]; then
    # Only list by default; you can uncomment the delete line if you want.
    run_cmd "find \"${HOME}/Downloads\" -type f -size +500M -mtime +${DAYS_OLD} -print"
    # To actually delete them, uncomment the line below:
    # run_cmd "find \"${HOME}/Downloads\" -type f -size +500M -mtime +${DAYS_OLD} -print -delete"
  else
    log "No ~/Downloads directory found."
  fi
}

########################################
# OPTIONAL EXTRAS (COMMENT IN IF NEEDED)
########################################

# Browser caches (can log you out, clear offline data)
clean_browser_caches() {
  header "Cleaning browser caches (optional; currently DISABLED)"

  # Google Chrome
  if [ -d "${HOME}/Library/Caches/Google/Chrome" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Google/Chrome\"/*"
  fi

  # Safari
  if [ -d "${HOME}/Library/Caches/com.apple.Safari" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/com.apple.Safari\"/*"
  fi

  # Firefox
  if [ -d "${HOME}/Library/Caches/Firefox" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Firefox\"/*"
  fi
}

# Developer / power-user cleanup (only if you actually use these tools)
clean_dev_stuff() {
  header "Developer / power-user cleanup (Homebrew, language caches, Docker, Xcode)"

  # Homebrew
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew detected – running cleanup."
    run_cmd "brew cleanup -s"
    run_cmd "brew autoremove"
  else
    log "Homebrew not found; skipping."
  fi

  # Common language/tool caches (pip, npm, yarn, pnpm)
  if [ -d "${HOME}/Library/Caches/pip" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/pip\"/*"
  fi
  if [ -d "${HOME}/.cache/pip" ]; then
    run_cmd "rm -rf \"${HOME}/.cache/pip\"/*"
  fi
  if [ -d "${HOME}/.npm" ]; then
    run_cmd "rm -rf \"${HOME}/.npm\"/*"
  fi
  if [ -d "${HOME}/Library/Caches/npm" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/npm\"/*"
  fi
  if [ -d "${HOME}/Library/Caches/Yarn" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Yarn\"/*"
  fi
  if [ -d "${HOME}/Library/pnpm/store" ]; then
    run_cmd "rm -rf \"${HOME}/Library/pnpm/store\"/*"
  fi

  # Docker (removes ALL unused containers/images/volumes)
  if command -v docker >/dev/null 2>&1; then
    log "Docker detected – pruning unused data."
    run_cmd "docker system prune -af --volumes"
  else
    log "Docker not found; skipping."
  fi

  # Xcode (only if present)
  if [ -d "${HOME}/Library/Developer/Xcode/DerivedData" ]; then
    log "Xcode DerivedData detected – cleaning."
    run_cmd "rm -rf \"${HOME}/Library/Developer/Xcode/DerivedData\"/*"
  fi
  if [ -d "${HOME}/Library/Developer/Xcode/Archives" ]; then
    log "Cleaning old Xcode Archives (older than ${DAYS_OLD} days)."
    run_cmd "find \"${HOME}/Library/Developer/Xcode/Archives\" -type d -mtime +${DAYS_OLD} -print -exec rm -rf {} +"
  fi
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
