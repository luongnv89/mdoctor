#!/usr/bin/env bash
#
# checks/usb.sh
# USB devices audit (read-only, SAFE)
# Category: Hardware
#

check_usb() {
  step "USB Devices"

  local usb_info
  usb_info=$(system_profiler SPUSBDataType 2>/dev/null || true)

  if [ -z "$usb_info" ]; then
    status_info "No USB information available."
    return 0
  fi

  # Count connected USB devices (lines containing product name pattern)
  local device_count=0
  local high_power_count=0
  local device_list=""
  local line current_device

  current_device=""

  while IFS= read -r line; do
    # Device name lines are indented and end with ":"
    local trimmed
    trimmed="${line#"${line%%[![:space:]]*}"}"

    # Check for product name
    if echo "$line" | grep -q "Product ID:"; then
      # We found a device entry
      true
    fi

    # Capture device names (non-Apple hub entries that have a colon at end)
    if echo "$trimmed" | grep -qE '^[A-Za-z].*:$' && ! echo "$trimmed" | grep -qiE 'USB Bus|Host Controller|hub'; then
      current_device="${trimmed%:}"
      device_count=$((device_count + 1))
      if [ -n "$device_list" ]; then
        device_list="${device_list}, ${current_device}"
      else
        device_list="${current_device}"
      fi
    fi

    # Check power draw (in mA)
    local power_ma
    power_ma=$(echo "$line" | awk -F': ' '/Current Available \(mA\)/ {gsub(/[^0-9]/,"",$2); print $2}')
    if [ -n "$power_ma" ] && (( power_ma > 500 )); then
      high_power_count=$((high_power_count + 1))
    fi
  done <<< "$usb_info"

  if (( device_count > 0 )); then
    status_ok "Connected USB devices: ${device_count}"
    if [ -n "$device_list" ]; then
      status_info "Devices: ${device_list}"
    fi
  else
    status_info "No USB devices connected."
  fi

  if (( high_power_count > 0 )); then
    status_info "USB ports providing high power (>500mA): ${high_power_count}"
  fi
}
