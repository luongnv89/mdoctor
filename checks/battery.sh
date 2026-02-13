#!/usr/bin/env bash
#
# checks/battery.sh
# Battery health check (read-only, SAFE)
# Category: Hardware
#

check_battery() {
  step "Battery Health"

  # Detect if this is a desktop Mac (no battery)
  local has_battery
  has_battery=$(system_profiler SPPowerDataType 2>/dev/null | grep -c "Battery Information" || true)

  if (( has_battery == 0 )); then
    status_info "No battery detected (desktop Mac). Skipping battery checks."
    return 0
  fi

  # Battery condition
  local condition
  condition=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Condition/ {print $2; exit}')
  if [ -n "$condition" ]; then
    if [ "$condition" = "Normal" ]; then
      status_ok "Battery condition: ${condition}"
    else
      status_fail "Battery condition: ${condition}"
      add_action "Battery condition is '${condition}'. Consider having it serviced."
    fi
  fi

  # Cycle count
  local cycle_count
  cycle_count=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Cycle Count/ {gsub(/ /,"",$2); print $2; exit}')
  if [ -n "$cycle_count" ]; then
    if (( cycle_count > 1000 )); then
      status_warn "Battery cycle count: ${cycle_count} (high — above 1000)"
      add_action "Battery has ${cycle_count} cycles. Performance may degrade. Consider replacement."
    else
      status_ok "Battery cycle count: ${cycle_count}"
    fi
  fi

  # Health percentage: AppleRawMaxCapacity / DesignCapacity
  local max_cap design_cap
  max_cap=$(ioreg -r -c AppleSmartBattery 2>/dev/null | grep '"AppleRawMaxCapacity" = ' | grep -o '[0-9]*$' | head -1)
  design_cap=$(ioreg -r -c AppleSmartBattery 2>/dev/null | grep '"DesignCapacity" = ' | grep -o '[0-9]*$' | head -1)

  if [ -n "$max_cap" ] && [ -n "$design_cap" ] && (( design_cap > 0 )); then
    local health_pct
    health_pct=$(( max_cap * 100 / design_cap ))
    if (( health_pct < 80 )); then
      status_warn "Battery health: ${health_pct}% (below 80%)"
      add_action "Battery health is at ${health_pct}%. Consider replacement for optimal performance."
    else
      status_ok "Battery health: ${health_pct}%"
    fi
  fi

  # Power source
  local power_source
  power_source=$(pmset -g batt 2>/dev/null | head -1 | sed "s/.*'//;s/'.*//" || true)
  if [ -n "$power_source" ]; then
    status_info "Power source: ${power_source}"
  fi

  # Charging status
  local charging
  charging=$(pmset -g batt 2>/dev/null | grep -o "charging\|discharging\|charged\|finishing charge" | head -1 || true)
  local batt_pct
  batt_pct=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 || true)
  if [ -n "$charging" ] && [ -n "$batt_pct" ]; then
    status_info "Battery: ${batt_pct} (${charging})"
  fi
}
