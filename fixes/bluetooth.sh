#!/usr/bin/env bash
#
# fixes/bluetooth.sh
# Reset Bluetooth module
# Risk: LOW — devices may need re-pairing
#

fix_bluetooth() {
  echo "${BOLD}${BLUE}== Resetting Bluetooth ==${RESET}"
  echo

  echo "${YELLOW}Note: Connected Bluetooth devices may need to be re-paired after reset.${RESET}"
  echo

  # Task 1.3: bluetoothd is BlueZ's daemon on Linux — signalling it would
  # bypass systemd supervision. macOS only.
  if ! is_macos; then
    echo "${YELLOW}Bluetooth fix is macOS-only — skipping on $(platform_name) (leaving the system Bluetooth daemon alone).${RESET}" >&2
    return 1
  fi

  echo "Restarting Bluetooth daemon..."
  sudo pkill -HUP bluetoothd 2>/dev/null || true

  echo "${GREEN}Bluetooth module reset. The daemon will auto-restart via launchd.${RESET}"
  echo "If devices disconnect, re-pair them from System Settings > Bluetooth."
}
