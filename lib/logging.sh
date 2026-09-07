#!/usr/bin/env bash
#
# lib/logging.sh
# Logging, markdown report generation, and persistent operation logging
#

# run_cmd_args needs is_dry_run (Task 1.6). Engines load lib/common.sh
# first, but cmd_fix and standalone sourcing may not — pull it in.
if ! declare -f is_dry_run >/dev/null 2>&1; then
  _MDOCTOR_LOGGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_LOGGING_DIR}/common.sh"
  unset _MDOCTOR_LOGGING_DIR
fi

########################################
# MARKDOWN REPORT
########################################

md_append() {
  local line="${1-}"
  [ -z "${REPORT_MD:-}" ] && return
  printf '%s\n' "$line" >> "$REPORT_MD"
}

md_init() {
  REPORT_MD="/tmp/mdoctor_report_$(date +%Y%m%d_%H%M%S).md"
  : > "$REPORT_MD"  # truncate/create
  md_append "# mdoctor System Health Report"
  md_append ""
  md_append "- Platform: **${MDOCTOR_OS_NAME:-$(uname -s)}**"
  md_append "- Generated on: **$(date)**"
  md_append "- Hostname: **$(hostname)**"
  md_append ""
}

########################################
# BASE LOGGING
########################################

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*" | tee -a "${LOGFILE:-/tmp/cleanup.log}"
}

debug_enabled() {
  [ "${MDOCTOR_DEBUG:-false}" = true ] || [ "${MDOCTOR_DEBUG:-0}" = "1" ]
}

debug_log() {
  debug_enabled || return 0
  local msg="$*"
  local line
  line="[$(timestamp)] [DEBUG] ${msg}"
  echo "$line" >&2
  printf '%s\n' "$line" >> "${LOGFILE:-/tmp/cleanup.log}"
  if declare -f op_record >/dev/null 2>&1; then
    op_record "DEBUG" "mdoctor" "$msg"
  fi
}

########################################
# PERSISTENT OPERATION LOG
########################################

OPLOGFILE="${OPLOGFILE:-${HOME}/.config/mdoctor/operations.log}"
OPLOG_ENABLED="${OPLOG_ENABLED:-true}"

OP_SESSION_NAME=""
OP_SESSION_START_EPOCH=""
OP_ACTION_COUNT=0
OP_ERROR_COUNT=0

oplog_enabled() {
  [ "${OPLOG_ENABLED:-true}" = true ]
}

oplog_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

oplog_ensure_file() {
  oplog_enabled || return 0
  local dir
  dir="$(dirname "$OPLOGFILE")"
  # Task 3.4: state is private at creation (0700 dirs, 0600 files).
  # Create-only (not unconditional chmod): this runs on every log write.
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    chmod 700 "$dir"
  fi
  if [ ! -f "$OPLOGFILE" ]; then
    : > "$OPLOGFILE"
    chmod 600 "$OPLOGFILE"
  fi
}

oplog_write() {
  oplog_enabled || return 0
  oplog_ensure_file
  printf '%s\n' "$*" >> "$OPLOGFILE"
}

op_session_start() {
  oplog_enabled || return 0
  local name="${1:-cleanup}"

  OP_SESSION_NAME="$name"
  OP_SESSION_START_EPOCH="$(date +%s 2>/dev/null || echo "")"
  OP_ACTION_COUNT=0
  OP_ERROR_COUNT=0

  oplog_write ""
  oplog_write "# === session start: ${name} @ $(oplog_timestamp) ==="
}

op_record() {
  oplog_enabled || return 0

  local action="${1:-UNKNOWN}"
  local target="${2:-}"
  local detail="${3:-}"

  OP_ACTION_COUNT=$((OP_ACTION_COUNT + 1))

  local line
  line="[$(oplog_timestamp)] [ACTION] ${action}"
  [ -n "$target" ] && line+=" target=${target}"
  [ -n "$detail" ] && line+=" detail=${detail}"

  oplog_write "$line"
}

op_error() {
  oplog_enabled || return 0

  local category="${1:-UNKNOWN}"
  local target="${2:-}"
  local detail="${3:-}"

  OP_ERROR_COUNT=$((OP_ERROR_COUNT + 1))

  local line
  line="[$(oplog_timestamp)] [ERROR] ${category}"
  [ -n "$target" ] && line+=" target=${target}"
  [ -n "$detail" ] && line+=" detail=${detail}"

  oplog_write "$line"
}

op_session_end() {
  oplog_enabled || return 0

  local status="${1:-ok}"
  local end_epoch
  end_epoch="$(date +%s 2>/dev/null || echo "")"

  local duration="unknown"
  if [[ "$OP_SESSION_START_EPOCH" =~ ^[0-9]+$ ]] && [[ "$end_epoch" =~ ^[0-9]+$ ]]; then
    duration=$((end_epoch - OP_SESSION_START_EPOCH))
  fi

  oplog_write "# === session end: ${OP_SESSION_NAME:-cleanup} status=${status} duration_s=${duration} actions=${OP_ACTION_COUNT} errors=${OP_ERROR_COUNT} @ $(oplog_timestamp) ==="
}

########################################
# COMMAND RUNNERS
########################################

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
    op_error "CMD_INVALID" "run_cmd_args" "called without command"
    return 1
  fi

  local cmd_display
  cmd_display=$(_format_cmd_for_log "$@")

  # Central fail-closed predicate (Task 1.6): only rc 1 (explicit
  # false/0/no/n) executes; unset/truthy/invalid values stay dry.
  local _dry_rc=0
  is_dry_run || _dry_rc=$?
  if [ "$_dry_rc" -ne 1 ]; then
    log "[DRY RUN] $cmd_display"
    debug_log "run_cmd_args dry-run command=${cmd_display}"
    op_record "DRY_RUN_CMD" "$cmd_display"
    return 0
  fi

  log "[RUN] $cmd_display"
  debug_log "run_cmd_args exec command=${cmd_display}"
  "$@"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "[ERROR] command failed (exit $rc): $cmd_display"
    debug_log "run_cmd_args failed exit=${rc} command=${cmd_display}"
    op_error "CMD_FAIL" "$cmd_display" "exit=$rc"
  else
    debug_log "run_cmd_args success command=${cmd_display}"
    op_record "RUN_CMD" "$cmd_display" "exit=0"
  fi
  return "$rc"
}

run_cmd_legacy() {
  local cmd="${1-}"
  if [ -z "$cmd" ]; then
    log "[ERROR] run_cmd_legacy called without command string"
    op_error "CMD_INVALID" "run_cmd_legacy" "called without command string"
    return 1
  fi

  # Central fail-closed predicate (Task 1.6): only rc 1 executes.
  local _dry_rc=0
  is_dry_run || _dry_rc=$?
  if [ "$_dry_rc" -ne 1 ]; then
    log "[DRY RUN][LEGACY] $cmd"
    debug_log "run_cmd_legacy dry-run command=${cmd}"
    op_record "DRY_RUN_CMD_LEGACY" "$cmd"
    return 0
  fi

  log "[RUN][LEGACY] $cmd"
  debug_log "run_cmd_legacy exec command=${cmd}"
  bash -c "$cmd"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    log "[ERROR] legacy command failed (exit $rc): $cmd"
    debug_log "run_cmd_legacy failed exit=${rc} command=${cmd}"
    op_error "CMD_FAIL_LEGACY" "$cmd" "exit=$rc"
  else
    debug_log "run_cmd_legacy success command=${cmd}"
    op_record "RUN_CMD_LEGACY" "$cmd" "exit=0"
  fi
  return "$rc"
}

run_cmd() {
  if [ "$#" -eq 0 ]; then
    log "[ERROR] run_cmd called without command"
    op_error "CMD_INVALID" "run_cmd" "called without command"
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
