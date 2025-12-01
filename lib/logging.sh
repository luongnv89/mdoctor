#!/usr/bin/env bash
#
# lib/logging.sh
# Logging and markdown report generation
#

########################################
# MARKDOWN REPORT
########################################

md_append() {
  local line="${1-}"
  [ -z "${REPORT_MD:-}" ] && return
  printf '%s\n' "$line" >> "$REPORT_MD"
}

md_init() {
  REPORT_MD="/tmp/macos_doctor_$(date +%Y%m%d_%H%M%S).md"
  : > "$REPORT_MD"  # truncate/create
  md_append "# macOS Doctor Report"
  md_append ""
  md_append "- Generated on: **$(date)**"
  md_append "- Hostname: **$(hostname)**"
  md_append ""
}

########################################
# CLEANUP LOGGING
########################################

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*" | tee -a "${LOGFILE:-/tmp/cleanup.log}"
}

run_cmd() {
  if [ "${DRY_RUN:-true}" = true ]; then
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
