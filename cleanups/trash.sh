#!/usr/bin/env bash
#
# cleanups/trash.sh
# Empty Trash
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
clean_trash() {
  local rc=0
  local trash_dir
  trash_dir="$(platform_trash_dir)"
  header "Emptying Trash (${trash_dir})"
  if is_linux; then
    # freedesktop.org Trash spec (issue #109): every files/<name> pairs
    # with info/<name>.trashinfo — deleting only the payload leaves
    # phantom entries in the desktop trash UI. Basenames are collected
    # before removal so each file's metadata entry is deleted alongside
    # it, then the info dir sweep clears orphaned entries. Every removal
    # routes through the same lib/safety.sh validators as the payload.
    local info_dir
    info_dir="$(platform_trash_info_dir)"
    if [ -d "$trash_dir" ]; then
      local item info_entry
      local info_entries=()
      for item in "$trash_dir"/* "$trash_dir"/.[!.]* "$trash_dir"/..?*; do
        [ -e "$item" ] || [ -L "$item" ] || continue
        info_entries+=("${info_dir}/${item##*/}.trashinfo")
      done
      safe_remove_children "$trash_dir" || rc=$?
      for info_entry in "${info_entries[@]+"${info_entries[@]}"}"; do
        if [ -e "$info_entry" ] || [ -L "$info_entry" ]; then
          safe_remove "$info_entry" || rc=$?
        fi
      done
    else
      log "Trash folder not found."
    fi
    if [ -n "$info_dir" ] && [ -d "$info_dir" ]; then
      safe_remove_children "$info_dir" || rc=$?
    fi
  elif [ -d "$trash_dir" ]; then
    safe_remove_children "$trash_dir" || rc=$?
  else
    log "Trash folder not found."
  fi
  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'trash' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'trash')"
  return "$rc"
}
