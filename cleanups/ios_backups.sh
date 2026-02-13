#!/usr/bin/env bash
#
# cleanups/ios_backups.sh
# List/remove old iOS device backups
# Risk: LOW
#

clean_ios_backups() {
  local days="${DAYS_OLD:-90}"
  local backup_dir="${HOME}/Library/Application Support/MobileSync/Backup"

  header "iOS device backups cleanup (older than ${days} days)"

  if [ ! -d "$backup_dir" ]; then
    log "No iOS backups directory found. Skipping."
    return 0
  fi

  local found=0
  local total_size_kb=0
  local d

  for d in "$backup_dir"/*/; do
    [ -d "$d" ] || continue
    found=$((found + 1))

    # Get backup size
    local size_kb
    size_kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    total_size_kb=$((total_size_kb + size_kb))

    # Get modification time
    local mod_date
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$d" 2>/dev/null || echo "unknown")

    local size_hr
    if (( size_kb >= 1048576 )); then
      size_hr=$(awk -v kb="$size_kb" 'BEGIN {printf "%.2f GB", kb/1048576}')
    elif (( size_kb >= 1024 )); then
      size_hr=$(awk -v kb="$size_kb" 'BEGIN {printf "%.1f MB", kb/1024}')
    else
      size_hr="${size_kb} KB"
    fi

    local backup_name
    backup_name=$(basename "$d")
    log "Backup: ${backup_name} — ${size_hr} (modified: ${mod_date})"
  done

  if (( found == 0 )); then
    log "No iOS backups found."
    return 0
  fi

  local total_hr
  if (( total_size_kb >= 1048576 )); then
    total_hr=$(awk -v kb="$total_size_kb" 'BEGIN {printf "%.2f GB", kb/1048576}')
  elif (( total_size_kb >= 1024 )); then
    total_hr=$(awk -v kb="$total_size_kb" 'BEGIN {printf "%.1f MB", kb/1024}')
  else
    total_hr="${total_size_kb} KB"
  fi

  log "Found ${found} backup(s) totaling ${total_hr}."

  # In force mode, remove backups older than threshold
  run_cmd "find \"${backup_dir}\" -mindepth 1 -maxdepth 1 -type d -mtime +${days} -print -exec rm -rf {} +"
}
