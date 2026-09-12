#!/usr/bin/env bash
#
# lib/disk.sh
# Disk-related utilities
#

# Named size/timeout values (Task 8.7); guarded so isolated sourcing works.
_MDOCTOR_DISK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
source "${_MDOCTOR_DISK_DIR}/constants.sh"
unset _MDOCTOR_DISK_DIR

# On macOS APFS, df / reports the read-only system snapshot which shows
# very little usage. The real user data lives on /System/Volumes/Data.
#
# The answer is constant for the life of the process (platform identity
# and the APFS Data-volume layout never change mid-run), so detection
# runs once and is cached in _MDOCTOR_DISK_ROOT (issue #98). In-library
# callers populate the cache with _disk_root_init and read the variable
# directly, skipping the command-substitution fork entirely; _disk_root
# stays the printing interface for external callers (checks/disk.sh).
_MDOCTOR_DISK_ROOT=""
_disk_root_init() {
  if [ -z "$_MDOCTOR_DISK_ROOT" ]; then
    # macOS APFS: real user data lives on the Data volume
    if is_macos 2>/dev/null && [ -d /System/Volumes/Data ]; then
      _MDOCTOR_DISK_ROOT="/System/Volumes/Data"
    else
      _MDOCTOR_DISK_ROOT="/"
    fi
  fi
}
_disk_root() {
  _disk_root_init
  printf '%s\n' "$_MDOCTOR_DISK_ROOT"
}

kb_to_human() {
  format_size_kb "${1:-0}"
}

disk_used_pct_root() {
  local out rc=0 value
  _disk_root_init
  out=$(df -H "$_MDOCTOR_DISK_ROOT" 2>/dev/null) || rc=$?
  if { [ "$rc" -ne 0 ] || [ -z "$out" ]; } && [ "$_MDOCTOR_DISK_ROOT" != "/" ]; then
    # Same fallback the retired caller spelled out: if the Data-volume
    # probe yields nothing, measure / (issue #98).
    rc=0
    out=$(df -H / 2>/dev/null) || rc=$?
  fi
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  # Row 2 carries the counters; field 5 is the Use% column. The
  # printf|awk extraction is now an in-shell split (issue #98).
  local _dfrow="" _d1 _d2 _d3 _d4 _drest _dfh
  {
    IFS= read -r _dfh || true    # header row
    IFS= read -r _dfrow || true  # data row (awk NR==2)
  } <<< "$out"
  value=""
  if [ -n "$_dfrow" ]; then
    read -r _d1 _d2 _d3 _d4 value _drest <<< "$_dfrow"
    value="${value//%/}"
  fi
  case "$value" in
    ''|*[!0-9]*) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac
  printf '%s\n' "$value"
}

disk_usage() {
  _disk_root_init
  local _df_out _dfrow="" _d1 _d2 _d3 _d4 _d5 _drest _dfh
  _df_out=$(df -h "$_MDOCTOR_DISK_ROOT" || true)
  {
    IFS= read -r _dfh || true
    IFS= read -r _dfrow || true
  } <<< "$_df_out"
  if [ -n "$_dfrow" ]; then
    read -r _d1 _d2 _d3 _d4 _d5 _drest <<< "$_dfrow"
    printf 'Disk usage: %s used / %s total (%s used)\n' "$_d3" "$_d2" "$_d5"
  fi
}

disk_used_kb() {
  local out rc=0 value
  _disk_root_init
  out=$(df -k "$_MDOCTOR_DISK_ROOT" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  # Same in-shell NR==2 row split; field 3 is the Used column.
  local _dfrow="" _d1 _d2 _drest _dfh
  {
    IFS= read -r _dfh || true
    IFS= read -r _dfrow || true
  } <<< "$out"
  value=""
  if [ -n "$_dfrow" ]; then
    read -r _d1 _d2 value _drest <<< "$_dfrow"
  fi
  case "$value" in
    ''|*[!0-9]*) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac
  printf '%s\n' "$value"
}

human_readable_kb() {
  local kb="$1"

  if (( kb < 0 )); then
    kb=$(( -kb ))
  fi

  format_size_kb "$kb"
}

# format_size_kb KB — the single size-formatter ladder (Task 8.2).
# Every other formatter in the repo is a wrapper around this one or a caller
# of it; no file re-inlines the GB/MB/KB ladder.
format_size_kb() {
  local kb="${1:-0}"
  if (( kb >= MDOCTOR_KB_PER_GB )); then
    awk -v kb="$kb" -v pergb="$MDOCTOR_KB_PER_GB" 'BEGIN {printf "%.2f GB", kb/pergb}'
  elif (( kb >= MDOCTOR_KB_PER_MB )); then
    awk -v kb="$kb" -v permb="$MDOCTOR_KB_PER_MB" 'BEGIN {printf "%.2f MB", kb/permb}'
  else
    printf "%d KB" "$kb"
  fi
}

# du_size_kb PATH — the single hardened du probe (Task 8.2, error channel
# added by Task 9.4 / issue #85).
#
# Prints a numeric KB value ONLY on success (rc 0). On failure prints
# nothing and returns a distinct non-zero code from the MDOCTOR_SIZE_ERR_*
# constants, so failure is never indistinguishable from an empty result:
#   0   — genuine measurement (may be 0 KB for an empty directory; when du
#         reports partial data because some subdirectories were unreadable,
#         the partial total is still a genuine, useful measurement)
#   MDOCTOR_SIZE_ERR_NO_TARGET   — path empty/missing ("not a directory")
#   MDOCTOR_SIZE_ERR_DENIED      — top-level target not readable/traversable
#   MDOCTOR_SIZE_ERR_TIMEOUT     — probe timed out
#   MDOCTOR_SIZE_ERR_FAILED      — any other measurement failure
#
# A top-level permission denial is detected before the probe (running as
# root bypasses mode checks, and du then succeeds — so under root the probe
# measures and returns 0, which is correct). Callers MUST branch on the
# return code; an unset result with rc 0 is never possible.
du_size_kb() {
  local path="${1-}"
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    return "$MDOCTOR_SIZE_ERR_NO_TARGET"
  fi
  # Top-level denial check: a directory needs +x (traverse), a file +r.
  # (Running as root bypasses mode checks — du then succeeds and the probe
  # measures normally, which is correct.) Nested unreadable subdirectories
  # still yield a partial du total; that partial size is a genuine,
  # useful measurement and keeps rc 0.
  if { [ -d "$path" ] && [ ! -x "$path" ]; } || { [ -f "$path" ] && [ ! -r "$path" ]; }; then
    return "$MDOCTOR_SIZE_ERR_DENIED"
  fi
  local kb_raw=""
  local probe_rc=0
  if command -v timeout >/dev/null 2>&1; then
    kb_raw=$(timeout "$MDOCTOR_DU_TIMEOUT_S" du -sk "$path" 2>/dev/null) || probe_rc=$?
  else
    kb_raw=$(du -sk "$path" 2>/dev/null) || probe_rc=$?
  fi
  if [ "$probe_rc" -eq 124 ]; then
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi
  if [ -z "$kb_raw" ]; then
    # No data at all: du died before printing anything (other failure).
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  # First line + numeric coercion: du prints the path after the size, and
  # the path itself may contain newlines (Task 3.6) — only the first line
  # carries the size. In-shell split replaces printf|awk (issue #98);
  # truncating at the first non-digit mirrors awk's $1+0 coercion.
  local _du_kb=""
  read -r _du_kb _ <<< "$kb_raw"
  _du_kb="${_du_kb%%[!0-9]*}"
  printf '%s\n' "${_du_kb:-0}"
  return 0
}
