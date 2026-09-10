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
    size_kb=$(du_size_kb "$d")
    total_size_kb=$((total_size_kb + size_kb))

    # Get modification time
    local mod_date
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$d" 2>/dev/null || echo "unknown")

    local size_hr
    size_hr=$(human_readable_kb "$size_kb")

    local backup_name
    backup_name=$(basename "$d")
    log "Backup: ${backup_name} — ${size_hr} (modified: ${mod_date})"
  done

  if (( found == 0 )); then
    log "No iOS backups found."
    return 0
  fi

  local total_hr
  total_hr=$(human_readable_kb "$total_size_kb")

  log "Found ${found} backup(s) totaling ${total_hr}."

  # In force mode, remove backups older than threshold
  safe_find_delete "${backup_dir}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" || true
}
