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
  df -H "$(_disk_root)" | awk 'NR==2 {gsub("%","",$5); print $5}'
}

disk_usage() {
  df -h "$(_disk_root)" | awk 'NR==2 {print "Disk usage: "$3" used / "$2" total ("$5" used)"}'
}

disk_used_kb() {
  df -k "$(_disk_root)" | awk 'NR==2 {print $3}'
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

# du_size_kb PATH — the single hardened du probe (Task 8.2), with a real
# error channel (Task 9.4).
# Echoes the size in KB (0 on failure, so bare arithmetic on the output
# stays safe) and returns 0 only for a genuine measurement:
#   $MDOCTOR_SIZE_ERR_NOT_DIR  path is missing (or vanished mid-probe)
#   $MDOCTOR_SIZE_ERR_TIMEOUT  the probe hit MDOCTOR_DU_TIMEOUT_S (rc 124)
#   $MDOCTOR_SIZE_ERR_DENIED   du failed with no usable size and reported
#                              a permission problem
#   du's own status            any other du failure with no usable size
# A partial read (a numeric size line plus unreadable-subdirectory noise)
# is still a genuine measurement: the size is echoed and 0 is returned, so
# pre-flight estimates under `set -e` never abort on a poisoned subdir.
# Callers that must tell failure from empty capture the status
# (out=$(du_size_kb "$p") || rc=$?) and report "could not determine"
# instead of treating 0 as "nothing to report".
du_size_kb() {
  local path="${1-}"
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    echo 0
    return "$MDOCTOR_SIZE_ERR_NOT_DIR"
  fi
  local out=""
  local du_rc=0
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$MDOCTOR_DU_TIMEOUT_S" du -sk "$path" 2>&1) || du_rc=$?
  else
    out=$(du -sk "$path" 2>&1) || du_rc=$?
  fi
  if [ "$du_rc" -eq 124 ]; then
    echo 0
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi
  # Last numeric-leading line wins: du prints "SIZE<TAB>path" on stdout
  # and "du: ..." diagnostics on stderr (combined above); only size lines
  # lead with a number, so diagnostics can never parse as a size.
  local kb=""
  kb=$(printf '%s\n' "$out" | awk '$1 ~ /^[0-9]+$/ {kb=$1} END {print kb+0}')
  if [ -n "$kb" ] && [ "$kb" != "0" ]; then
    echo "$kb"
    return 0
  fi
  if [ "$du_rc" -ne 0 ]; then
    case "$out" in
      *"Permission denied"*|*"Operation not permitted"*)
        echo 0
        return "$MDOCTOR_SIZE_ERR_DENIED"
        ;;
      *"No such file"*)
        echo 0
        return "$MDOCTOR_SIZE_ERR_NOT_DIR"
        ;;
      *)
        echo 0
        return "$du_rc"
        ;;
    esac
  fi
  echo 0
  return 0
}

# dir_size_kb PATH — the documented probe name (Task 9.4 verify command);
# identical output and error channel to du_size_kb.
dir_size_kb() {
  du_size_kb "$@"
}
