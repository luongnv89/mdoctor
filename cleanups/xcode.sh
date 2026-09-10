#!/usr/bin/env bash
#
# cleanups/xcode.sh
# Xcode-specific cleanup (DerivedData, Archives, Simulators)
# Risk: LOW
#

clean_xcode() {
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
      safe_remove_children "${derived_data}" || true
    fi
  else
    log "No Xcode DerivedData directory found."
  fi

  # Old Archives (older than threshold)
  local archives="${HOME}/Library/Developer/Xcode/Archives"
  if [ -d "$archives" ]; then
    log "Cleaning Xcode Archives older than ${days} days..."
    safe_find_delete "${archives}" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" || true
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
      safe_remove_children "${sim_caches}" || true
    fi
  fi
}
