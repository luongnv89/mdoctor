#!/usr/bin/env bash
#
# lib/logging.sh
# Logging, markdown report generation, and persistent operation logging
#

# run_cmd_args needs is_dry_run (Task 1.6), md_init needs
# mdoctor_mktemp_file (Task 4.3). Engines load lib/common.sh first, but
# cmd_fix and standalone sourcing may not — pull it in.
if ! declare -f is_dry_run >/dev/null 2>&1 || ! declare -f mdoctor_mktemp_file >/dev/null 2>&1; then
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
  # Deterministic report path (issue #74): automation and tests set
  # MDOCTOR_REPORT_MD to assert on the report's location and content.
  # Otherwise a fresh secure temp file is used, as before.
  if [ -n "${MDOCTOR_REPORT_MD:-}" ]; then
    REPORT_MD="$MDOCTOR_REPORT_MD"
  else
    REPORT_MD="$(mdoctor_mktemp_file mdoctor-report)"
  fi
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

# --- Fork-free timestamps (issue #99) -------------------------------------
# The issue proposed printf '%(...)T', but that conversion is Bash 4.2+ and
# the 3.2 floor is an invariant, so timestamps are derived without any
# per-call process: a single `date '+%s %z'` exec seeds the epoch and the
# local UTC offset once per process, SECONDS supplies per-call deltas, and
# a civil-from-days conversion (Hinnant's algorithm) renders local time in
# pure arithmetic. Cost per call after seeding: zero forks, zero execs.
# Known limit: the UTC offset is sampled at seed time — a process spanning
# a DST transition keeps the seeded offset until restart (identical class
# of staleness as a cached `date` call; sessions are minutes, not days).
_MDOCTOR_TS_SEED_EPOCH=""
_MDOCTOR_TS_SEED_SECONDS=""
_MDOCTOR_TS_OFFSET=""
_MDOCTOR_TS_EPOCH=""
_MDOCTOR_TS_FMT=""
_MDOCTOR_TS_FMT_EPOCH=""

# One `date '+%s %z'` exec: epoch + offset (e.g. "1789247417 +0200").
# Returns 1 when `date` is unavailable so callers fall back to exec'ing it.
_mdoctor_ts_seed() {
  local out epoch z zd sign hh mm
  out="$(date '+%s %z' 2>/dev/null)"
  _MDOCTOR_TS_SEED_SECONDS=$SECONDS
  epoch="${out%% *}"
  case "$epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac
  z="${out##* }"
  sign=1
  case "$z" in
    -*) sign=-1; zd="${z#-}" ;;
    +*) zd="${z#+}" ;;
    *)  zd="" ;;
  esac
  zd="${zd//:/}"
  while [ "${#zd}" -lt 4 ] && [ -n "$zd" ]; do zd="0$zd"; done
  case "$zd" in
    ''|*[!0-9]*) _MDOCTOR_TS_OFFSET=0 ;;
    *)
      if [ "${#zd}" -eq 4 ]; then
        hh="10#${zd%??}"
        mm="10#${zd#??}"
        _MDOCTOR_TS_OFFSET=$(( sign * (hh * 3600 + mm * 60) ))
      else
        _MDOCTOR_TS_OFFSET=0
      fi
      ;;
  esac
  _MDOCTOR_TS_SEED_EPOCH=$epoch
  _MDOCTOR_TS_FMT_EPOCH=""
  return 0
}

# Current epoch from the seed + SECONDS delta (pure arithmetic).
_mdoctor_ts_epoch_now() {
  if [ -z "$_MDOCTOR_TS_SEED_EPOCH" ]; then
    _mdoctor_ts_seed || return 1
  fi
  local now=$(( _MDOCTOR_TS_SEED_EPOCH + SECONDS - _MDOCTOR_TS_SEED_SECONDS ))
  if [ "$now" -lt "$_MDOCTOR_TS_SEED_EPOCH" ]; then
    # SECONDS was reset under us — reseed rather than print garbage.
    _mdoctor_ts_seed || return 1
    now=$(( _MDOCTOR_TS_SEED_EPOCH + SECONDS - _MDOCTOR_TS_SEED_SECONDS ))
  fi
  _MDOCTOR_TS_EPOCH=$now
  return 0
}

# Civil-from-days on the local-shifted epoch (Hinnant's algorithm),
# rendered by one printf builtin into _MDOCTOR_TS_FMT.
_mdoctor_ts_format() {
  local l days sod hh mm ss zd era doe yoe y doy mp d m
  l=$(( _MDOCTOR_TS_EPOCH + _MDOCTOR_TS_OFFSET ))
  days=$(( l / 86400 ))
  sod=$(( l - days * 86400 ))
  if [ "$sod" -lt 0 ]; then
    days=$(( days - 1 ))
    sod=$(( sod + 86400 ))
  fi
  hh=$(( sod / 3600 ))
  mm=$(( (sod % 3600) / 60 ))
  ss=$(( sod % 60 ))
  zd=$(( days + 719468 ))
  if [ "$zd" -ge 0 ]; then
    era=$(( zd / 146097 ))
  else
    era=$(( (zd - 146096) / 146097 ))
  fi
  doe=$(( zd - era * 146097 ))
  yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
  y=$(( yoe + era * 400 ))
  doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
  mp=$(( (5 * doy + 2) / 153 ))
  d=$(( doy - (153 * mp + 2) / 5 + 1 ))
  if [ "$mp" -lt 10 ]; then
    m=$(( mp + 3 ))
  else
    m=$(( mp - 9 ))
  fi
  if [ "$m" -le 2 ]; then
    y=$(( y + 1 ))
  fi
  printf -v _MDOCTOR_TS_FMT '%04d-%02d-%02d %02d:%02d:%02d' \
    "$y" "$m" "$d" "$hh" "$mm" "$ss"
}

# Refresh the formatted timestamp when the second ticked (per-second cache).
_mdoctor_ts_now() {
  _mdoctor_ts_epoch_now || return 1
  if [ "$_MDOCTOR_TS_EPOCH" != "$_MDOCTOR_TS_FMT_EPOCH" ]; then
    _mdoctor_ts_format
    _MDOCTOR_TS_FMT_EPOCH=$_MDOCTOR_TS_EPOCH
  fi
  return 0
}

# _mdoctor_ts VAR — assign "YYYY-MM-DD HH:MM:SS" to VAR with no fork.
# Falls back to a `date` exec only when seeding is impossible.
_mdoctor_ts() {
  if _mdoctor_ts_now; then
    printf -v "$1" '%s' "$_MDOCTOR_TS_FMT"
  else
    printf -v "$1" '%s' "$(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

timestamp() {
  local _ts
  _mdoctor_ts _ts
  printf '%s\n' "$_ts"
}

log() {
  local _ts line
  if _mdoctor_ts_now; then
    _ts="$_MDOCTOR_TS_FMT"
  else
    _ts="$(date '+%Y-%m-%d %H:%M:%S')"
  fi
  line="[${_ts}] $*"
  # Plain append replaces echo|tee -a (issue #99): two builtins, one
  # open/append/close, zero forks — stdout copy first, like tee.
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "${LOGFILE:-/tmp/cleanup.log}"
}

debug_enabled() {
  # One truthy predicate (Task 9.5): true/1/yes/y accepted alike, so
  # MDOCTOR_DEBUG=1 enables debug logging everywhere consistently.
  is_truthy "${MDOCTOR_DEBUG:-false}"
}

debug_log() {
  debug_enabled || return 0
  local msg="$*"
  local _ts line
  _mdoctor_ts _ts
  line="[${_ts}] [DEBUG] ${msg}"
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
  is_truthy "${OPLOG_ENABLED:-true}"
}

oplog_timestamp() {
  timestamp
}

# Set to the OPLOGFILE path once its directory/permissions have been
# ensured this process (issue #99): oplog_ensure_file used to fork
# `dirname` plus a mkdir/stat pass on EVERY write.
_MDOCTOR_OPLOG_READY=""

oplog_ensure_file() {
  oplog_enabled || return 0
  # Once per OPLOGFILE per process: hoisted to op_session_start and gated
  # here so session-less callers (tests, debug_log) still get one ensure.
  # The -f test keeps the gate honest when the file is deleted mid-session:
  # fall through to recreate it (0600) rather than letting the append in
  # oplog_write re-create it at umask permissions (Task 3.4 guarantee).
  if [ "$_MDOCTOR_OPLOG_READY" = "$OPLOGFILE" ] && [ -f "$OPLOGFILE" ]; then
    return 0
  fi
  local dir
  dir="$(dirname "$OPLOGFILE")"
  # Task 3.4: state is private at creation (0700 dirs, 0600 files).
  # Create-only (not unconditional chmod).
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    chmod 700 "$dir"
  fi
  if [ ! -f "$OPLOGFILE" ]; then
    : > "$OPLOGFILE"
    chmod 600 "$OPLOGFILE"
  fi
  _MDOCTOR_OPLOG_READY="$OPLOGFILE"
}

oplog_write() {
  oplog_enabled || return 0
  # Issue #99: the dirname/mkdir ensure is once per OPLOGFILE, not per
  # write — steady state is the builtin gate inside oplog_ensure_file
  # (which also catches a mid-session file deletion) plus this append.
  oplog_ensure_file
  printf '%s\n' "$*" >> "$OPLOGFILE"
}

op_session_start() {
  oplog_enabled || return 0
  local name="${1:-cleanup}"

  OP_SESSION_NAME="$name"
  if _mdoctor_ts_epoch_now; then
    OP_SESSION_START_EPOCH="$_MDOCTOR_TS_EPOCH"
  else
    OP_SESSION_START_EPOCH="$(date +%s 2>/dev/null || echo "")"
  fi
  OP_ACTION_COUNT=0
  OP_ERROR_COUNT=0

  local _ts
  _mdoctor_ts _ts
  oplog_ensure_file
  oplog_write ""
  oplog_write "# === session start: ${name} @ ${_ts} ==="
}

op_record() {
  oplog_enabled || return 0

  local action="${1:-UNKNOWN}"
  local target="${2:-}"
  local detail="${3:-}"

  OP_ACTION_COUNT=$((OP_ACTION_COUNT + 1))

  local _ts line
  if _mdoctor_ts_now; then
    _ts="$_MDOCTOR_TS_FMT"
  else
    _ts="$(date '+%Y-%m-%d %H:%M:%S')"
  fi
  line="[${_ts}] [ACTION] ${action}"
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

  local _ts line
  if _mdoctor_ts_now; then
    _ts="$_MDOCTOR_TS_FMT"
  else
    _ts="$(date '+%Y-%m-%d %H:%M:%S')"
  fi
  line="[${_ts}] [ERROR] ${category}"
  [ -n "$target" ] && line+=" target=${target}"
  [ -n "$detail" ] && line+=" detail=${detail}"

  oplog_write "$line"
}

op_session_end() {
  oplog_enabled || return 0

  local status="${1:-ok}"
  local end_epoch
  if _mdoctor_ts_epoch_now; then
    end_epoch="$_MDOCTOR_TS_EPOCH"
  else
    end_epoch="$(date +%s 2>/dev/null || echo "")"
  fi

  local duration="unknown"
  if [[ "$OP_SESSION_START_EPOCH" =~ ^[0-9]+$ ]] && [[ "$end_epoch" =~ ^[0-9]+$ ]]; then
    duration=$((end_epoch - OP_SESSION_START_EPOCH))
  fi

  local _ts
  _mdoctor_ts _ts
  oplog_write "# === session end: ${OP_SESSION_NAME:-cleanup} status=${status} duration_s=${duration} actions=${OP_ACTION_COUNT} errors=${OP_ERROR_COUNT} @ ${_ts} ==="
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

header() {
  echo
  log "========== $* =========="
}
