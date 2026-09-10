#!/usr/bin/env bash
#
# cleanups/ios_backups.sh
# List/remove old iOS device backups
# Risk: LOW
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_ios_backups() {
  local rc=0
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
  safe_find_delete "${backup_dir}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" || rc=$?
  handle_cleanup_rc "$rc" || rc=$?
  [ "$rc" -eq 0 ] || log "Module 'ios_backups' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'ios_backups')"
  return "$rc"
}
