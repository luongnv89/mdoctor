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

_format_cmd_for_log() {
  local out=""
  local arg=""

  for arg in "$@"; do
    local quoted
    quoted=$(printf "%q" "$arg")
    if [ -z "$out" ]; then
      out="$quoted"
    else
      out="$out $quoted"
    fi
  done

  printf '%s' "$out"
}

run_cmd_args() {
  if [ "$#" -eq 0 ]; then
    log "[ERROR] run_cmd_args called without command"
    return 1
  fi

  local cmd_display
  cmd_display=$(_format_cmd_for_log "$@")

  if [ "${DRY_RUN:-true}" = true ]; then
    log "[DRY RUN] $cmd_display"
    return 0
  fi

  log "[RUN] $cmd_display"
  "$@"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "[ERROR] command failed (exit $rc): $cmd_display"
  fi
  return "$rc"
}

run_cmd_legacy() {
  local cmd="${1-}"
  if [ -z "$cmd" ]; then
    log "[ERROR] run_cmd_legacy called without command string"
    return 1
  fi

  if [ "${DRY_RUN:-true}" = true ]; then
    log "[DRY RUN][LEGACY] $cmd"
    return 0
  fi

  log "[RUN][LEGACY] $cmd"
  bash -c "$cmd"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "[ERROR] legacy command failed (exit $rc): $cmd"
  fi
  return "$rc"
}

run_cmd() {
  if [ "$#" -eq 0 ]; then
    log "[ERROR] run_cmd called without command"
    return 1
  fi

  if [ "$#" -eq 1 ]; then
    run_cmd_legacy "$1"
  else
    run_cmd_args "$@"
  fi
}

header() {
  echo
  log "========== $* =========="
}
