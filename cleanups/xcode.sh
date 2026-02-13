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
    dd_size=$(du -sk "$derived_data" 2>/dev/null | awk '{print $1}')
    if (( dd_size > 0 )); then
      local dd_hr
      if (( dd_size >= 1048576 )); then
        dd_hr=$(awk -v kb="$dd_size" 'BEGIN {printf "%.2f GB", kb/1048576}')
      elif (( dd_size >= 1024 )); then
        dd_hr=$(awk -v kb="$dd_size" 'BEGIN {printf "%.1f MB", kb/1024}')
      else
        dd_hr="${dd_size} KB"
      fi
      log "Xcode DerivedData: ${dd_hr}"
      run_cmd "rm -rf \"${derived_data}\"/*"
    fi
  else
    log "No Xcode DerivedData directory found."
  fi

  # Old Archives (older than threshold)
  local archives="${HOME}/Library/Developer/Xcode/Archives"
  if [ -d "$archives" ]; then
    log "Cleaning Xcode Archives older than ${days} days..."
    run_cmd "find \"${archives}\" -type d -mindepth 1 -maxdepth 1 -mtime +${days} -print -exec rm -rf {} +"
  fi

  # Unavailable simulators
  if command -v xcrun >/dev/null 2>&1; then
    log "Removing unavailable simulators..."
    run_cmd "xcrun simctl delete unavailable"
  fi

  # Simulator caches
  local sim_caches="${HOME}/Library/Developer/CoreSimulator/Caches"
  if [ -d "$sim_caches" ]; then
    local sc_size
    sc_size=$(du -sk "$sim_caches" 2>/dev/null | awk '{print $1}')
    if (( sc_size > 1024 )); then
      local sc_hr
      if (( sc_size >= 1048576 )); then
        sc_hr=$(awk -v kb="$sc_size" 'BEGIN {printf "%.2f GB", kb/1048576}')
      elif (( sc_size >= 1024 )); then
        sc_hr=$(awk -v kb="$sc_size" 'BEGIN {printf "%.1f MB", kb/1024}')
      else
        sc_hr="${sc_size} KB"
      fi
      log "Simulator caches: ${sc_hr}"
      run_cmd "rm -rf \"${sim_caches}\"/*"
    fi
  fi
}
