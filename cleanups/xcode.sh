#!/usr/bin/env bash
#
# cleanups/xcode.sh
# Xcode-specific cleanup (DerivedData, Archives, Simulators)
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
clean_xcode() {
  local rc=0
  local days="${DAYS_OLD:-30}"
  header "Xcode cleanup"

  # DerivedData (safe — rebuilt on next build)
  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [ -d "$derived_data" ]; then
    local dd_size
    dd_size=$(du_size_kb "$derived_data")
    if (( dd_size > 0 )); then
      local dd_hr
      dd_hr=$(human_readable_kb "$dd_size")
      log "Xcode DerivedData: ${dd_hr}"
      safe_remove_children "${derived_data}" || rc=$?
    fi
  else
    log "No Xcode DerivedData directory found."
  fi

  # Old Archives (older than threshold)
  local archives="${HOME}/Library/Developer/Xcode/Archives"
  if [ -d "$archives" ]; then
    log "Cleaning Xcode Archives older than ${days} days..."
    safe_find_delete "${archives}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" || rc=$?
  fi

  # Unavailable simulators
  if command -v xcrun >/dev/null 2>&1; then
    log "Removing unavailable simulators..."
    run_cmd_args xcrun simctl delete unavailable
  fi

  # Simulator caches
  local sim_caches="${HOME}/Library/Developer/CoreSimulator/Caches"
  if [ -d "$sim_caches" ]; then
    local sc_size
    sc_size=$(du_size_kb "$sim_caches")
    if (( sc_size > 1024 )); then
      local sc_hr
      sc_hr=$(human_readable_kb "$sc_size")
      log "Simulator caches: ${sc_hr}"
      safe_remove_children "${sim_caches}" || rc=$?
    fi
  fi
  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'xcode' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'xcode')"
  return "$rc"
}
