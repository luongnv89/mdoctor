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
  # The output has sections "Connected:" and "Not Connected:" with device names
  # as indented headers (e.g. "          MX Anywhere 3S:") followed by properties.
  # We parse between "Connected:" and "Not Connected:" sections.
  local in_connected=0
  local connected_count=0
  local device_lines=""
  local line

  while IFS= read -r line; do
    # Match the top-level "Connected:" section header (6 leading spaces)
    if echo "$line" | grep -qE '^      Connected:$'; then
      in_connected=1
      continue
    fi
    # Stop at "Not Connected:" section or any other top-level section
    if (( in_connected == 1 )) && echo "$line" | grep -qE '^      [A-Z]'; then
      in_connected=0
      continue
    fi
    # Device names are indented with ~10 spaces and end with ":"
    # but are NOT property lines (which contain ": " with a value)
    if (( in_connected == 1 )); then
      local trimmed
      trimmed="${line#"${line%%[![:space:]]*}"}"
      # Device header: "DeviceName:" with no value after the colon
      if echo "$trimmed" | grep -qE '^.+:$'; then
        local dev_name
        dev_name="${trimmed%:}"
        connected_count=$((connected_count + 1))
        local dev_type=""
        # Look ahead for Minor Type in subsequent lines
        dev_type=$(echo "$bt_info" | awk -v dev="$trimmed" '
          $0 ~ dev {found=1; next}
          found && /Minor Type:/ {sub(/.*Minor Type: */, ""); print; exit}
          found && /^          [^ ]/ {exit}
        ')
        if [ -n "$dev_type" ]; then
          device_lines="${device_lines}${dev_name} (${dev_type})\n"
        else
          device_lines="${device_lines}${dev_name}\n"
        fi
      fi
    fi
  done <<< "$bt_info"

  if (( connected_count > 0 )); then
    status_info "Connected Bluetooth devices: ${connected_count}"
    echo -e "$device_lines" | while IFS= read -r dline; do
      [ -n "$dline" ] && status_info "  ${dline}"
    done
  else
    status_info "No Bluetooth devices connected."
  fi
}
