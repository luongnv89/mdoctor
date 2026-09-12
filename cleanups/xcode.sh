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

# Size-cache bootstrap (Task 11.2): both entry points source
# lib/preflight.sh before any module; a standalone `source` (unit tests)
# may not have — pull it in when its entry point is missing so the
# per-process size cache the modules read is always available.
if ! declare -f size_cache_kb >/dev/null 2>&1; then
  _MDOCTOR_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_MODULE_DIR}/../lib/disk.sh"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_MODULE_DIR}/../lib/preflight.sh"
  unset _MDOCTOR_MODULE_DIR
fi

clean_xcode() {
  local rc=0
  local days="${DAYS_OLD:-30}"
  header "Xcode cleanup (older than ${days} days)"

  # DerivedData (safe — rebuilt on next build). Task 11.2: the size comes
  # from the keyed per-process cache — the force-mode pre-flight already
  # measured this root, so the tree is walked once, not three times.
  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [ -d "$derived_data" ]; then
    local dd_size dd_rc=0
    size_cache_kb "$derived_data" || dd_rc=$?
    dd_size="${MDOCTOR_SIZE_KB:-}"
    if [ "$dd_rc" -ne 0 ]; then
      log "Xcode DerivedData: could not determine, skipping."
    elif (( dd_size > 0 )); then
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

  # Simulator caches (same size-cache path as DerivedData, Task 11.2).
  local sim_caches="${HOME}/Library/Developer/CoreSimulator/Caches"
  if [ -d "$sim_caches" ]; then
    local sc_size sc_rc=0
    size_cache_kb "$sim_caches" || sc_rc=$?
    sc_size="${MDOCTOR_SIZE_KB:-}"
    if [ "$sc_rc" -ne 0 ]; then
      log "Simulator caches: could not determine, skipping."
    elif (( sc_size > 1024 )); then
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
