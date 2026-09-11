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
_disk_root() {
  # macOS APFS: real user data lives on the Data volume
  if is_macos 2>/dev/null && [ -d /System/Volumes/Data ]; then
    echo /System/Volumes/Data
  else
    echo /
  fi
}

kb_to_human() {
  format_size_kb "${1:-0}"
}

disk_used_pct_root() {
  local out rc=0 value
  out=$(df -H "$(_disk_root)" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  value=$(printf '%s\n' "$out" | awk 'NR==2 {gsub("%","",$5); print $5}') || return "$MDOCTOR_SIZE_ERR_FAILED"
  case "$value" in
    ''|*[!0-9]*) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac
  printf '%s\n' "$value"
}

disk_usage() {
  df -h "$(_disk_root)" | awk 'NR==2 {print "Disk usage: "$3" used / "$2" total ("$5" used)"}'
}

disk_used_kb() {
  local out rc=0 value
  out=$(df -k "$(_disk_root)" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    return "$MDOCTOR_SIZE_ERR_FAILED"
  fi
  value=$(printf '%s\n' "$out" | awk 'NR==2 {print $3}') || return "$MDOCTOR_SIZE_ERR_FAILED"
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
  # NR==1 + numeric coercion: du prints the path after the size, and the
  # path itself may contain newlines (Task 3.6) — only the first line
  # carries the size.
  printf '%s\n' "$kb_raw" | awk 'NR==1{print $1+0}'
  return 0
}
