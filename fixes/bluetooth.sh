#!/usr/bin/env bash
#
# fixes/bluetooth.sh
# Reset Bluetooth module
# Risk: LOW — devices may need re-pairing
#

fix_bluetooth() {
  header "Resetting Bluetooth"

  echo "${YELLOW}Note: Connected Bluetooth devices may need to be re-paired after reset.${RESET}"
  echo

  # Task 1.3: bluetoothd is BlueZ's daemon on Linux — signalling it would
  # bypass systemd supervision. macOS only.
  if ! is_macos; then
    echo "${YELLOW}Bluetooth fix is macOS-only — skipping on $(platform_name) (leaving the system Bluetooth daemon alone).${RESET}" >&2
    return 1
  fi

  echo "Restarting Bluetooth daemon..."
  if run_cmd_args sudo pkill -HUP bluetoothd 2>/dev/null; then
    status_ok "Bluetooth module reset. The daemon will auto-restart via launchd."
    echo "If devices disconnect, re-pair them from System Settings > Bluetooth."
    return 0
  else
    status_warn "Could not reset the Bluetooth module."
    return 1
  fi
}
