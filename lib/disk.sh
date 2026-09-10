#!/usr/bin/env bash
#
# lib/disk.sh
# Disk-related utilities
#

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
  if (( kb >= 1048576 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f GB", kb/1048576}'
  elif (( kb >= 1024 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f MB", kb/1024}'
  else
    printf "%d KB" "$kb"
  fi
}

# du_size_kb PATH — the single hardened du probe (Task 8.2).
# Never propagates a non-zero du status (permission-denied subdirectories
# must not abort callers running under `set -e` / `pipefail`); always prints
# a numeric KB value (0 on failure). Wraps the probe in `timeout 30` where
# available (GNU-only; macOS runs it directly). Every du call site routes
# through this.
du_size_kb() {
  local path="${1-}"
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    echo 0
    return 0
  fi
  local kb=""
  # NR==1 + numeric coercion: du prints the path after the size, and the
  # path itself may contain newlines (Task 3.6) — only the first line
  # carries the size.
  if command -v timeout >/dev/null 2>&1; then
    kb=$({ timeout 30 du -sk "$path" 2>/dev/null || true; } | awk 'NR==1{print $1+0}')
  else
    kb=$({ du -sk "$path" 2>/dev/null || true; } | awk 'NR==1{print $1+0}')
  fi
  echo "${kb:-0}"
}
