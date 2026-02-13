#!/usr/bin/env bash
#
# checks/bluetooth.sh
# Bluetooth status check (read-only, SAFE)
# Category: Hardware
#

check_bluetooth() {
  step "Bluetooth Status"

  local bt_info
  bt_info=$(system_profiler SPBluetoothDataType 2>/dev/null || true)

  if [ -z "$bt_info" ]; then
    status_info "Bluetooth information not available."
    return 0
  fi

  # Bluetooth power state
  local bt_state
  bt_state=$(echo "$bt_info" | awk -F': ' '/State:/ {print $2; exit}' | tr -d '[:space:]')
  if [ -z "$bt_state" ]; then
    # Try alternative: defaults read
    bt_state=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo "")
    if [ "$bt_state" = "1" ]; then
      bt_state="On"
    elif [ "$bt_state" = "0" ]; then
      bt_state="Off"
    fi
  fi

  if [ -n "$bt_state" ]; then
    if [ "$bt_state" = "On" ] || [ "$bt_state" = "Attivo" ]; then
      status_ok "Bluetooth: On"
    else
      status_info "Bluetooth: ${bt_state}"
    fi
  fi

  # Bluetooth hardware version / chipset
  local bt_chipset
  bt_chipset=$(echo "$bt_info" | awk -F': ' '/Chipset:/ {print $2; exit}')
  if [ -n "$bt_chipset" ]; then
    status_info "Bluetooth chipset: ${bt_chipset}"
  fi

  # Connected devices
  local connected_count=0
  local device_names=""
  local in_connected=0
  local line

  while IFS= read -r line; do
    # Detect "Connected:" section
    if echo "$line" | grep -q "Connected: Yes"; then
      in_connected=1
    fi
    # Collect device names (lines with "Name:" under connected devices)
    if (( in_connected == 1 )); then
      local name
      name=$(echo "$line" | awk -F': ' '/^[[:space:]]*Name:/ {print $2}')
      if [ -n "$name" ]; then
        connected_count=$((connected_count + 1))
        if [ -n "$device_names" ]; then
          device_names="${device_names}, ${name}"
        else
          device_names="${name}"
        fi
      fi
    fi
  done <<< "$bt_info"

  # Simpler approach: count connected devices
  local connected
  connected=$(echo "$bt_info" | grep -c "Connected: Yes" || true)
  if (( connected > 0 )); then
    status_info "Connected Bluetooth devices: ${connected}"
  else
    status_info "No Bluetooth devices connected."
  fi
}
