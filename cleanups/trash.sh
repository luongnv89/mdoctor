#!/usr/bin/env bash
#
# cleanups/trash.sh
# Empty Trash
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_trash() {
  local trash_dir
  trash_dir="$(platform_trash_dir)"
  header "Emptying Trash (${trash_dir})"
  if [ -d "$trash_dir" ]; then
    safe_remove_children "$trash_dir" || true
  else
    log "Trash folder not found."
  fi
}
