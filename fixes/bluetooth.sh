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

  echo "Restarting Bluetooth daemon..."
  sudo pkill -HUP bluetoothd 2>/dev/null || true

  echo "${GREEN}Bluetooth module reset. The daemon will auto-restart via launchd.${RESET}"
  echo "If devices disconnect, re-pair them from System Settings > Bluetooth."
}
