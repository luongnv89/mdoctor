#!/usr/bin/env bash
#
# lib/disk.sh
# Disk-related utilities
#

kb_to_human() {
  local kb="${1:-0}"
  if (( kb >= 1048576 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f GB", kb/1048576}'
  elif (( kb >= 1024 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f MB", kb/1024}'
  else
    printf "%d KB" "$kb"
  fi
}

disk_used_pct_root() {
  df -H / | awk 'NR==2 {gsub("%","",$5); print $5}'
}

disk_usage() {
  df -h / | awk 'NR==2 {print "Disk usage: "$3" used / "$2" total ("$5" used)"}'
}

disk_used_kb() {
  df -k / | awk 'NR==2 {print $3}'
}

human_readable_kb() {
  local kb="$1"

  if (( kb < 0 )); then
    kb=$(( -kb ))
  fi

  if (( kb >= 1048576 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f GB", kb/1048576}'
  elif (( kb >= 1024 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f MB", kb/1024}'
  else
    printf "%d KB" "$kb"
  fi
}
