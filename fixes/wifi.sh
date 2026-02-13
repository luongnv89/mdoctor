#!/usr/bin/env bash
#
# fixes/wifi.sh
# 3-step Wi-Fi fix: renew DHCP, flush DNS, cycle Wi-Fi
# Risk: LOW
#

fix_wifi() {
  echo "${BOLD}${BLUE}== Fixing Wi-Fi ==${RESET}"
  echo

  # Detect active Wi-Fi interface
  local wifi_if
  wifi_if=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2}')
  if [ -z "$wifi_if" ]; then
    # Fallback: try en0 (common default)
    wifi_if="en0"
  fi

  echo "Detected Wi-Fi interface: ${wifi_if}"
  echo

  echo "${CYAN}[1/3]${RESET} Renewing DHCP lease..."
  sudo ipconfig set "$wifi_if" DHCP 2>/dev/null || true

  echo "${CYAN}[2/3]${RESET} Flushing DNS cache..."
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true

  echo "${CYAN}[3/3]${RESET} Cycling Wi-Fi off/on..."
  networksetup -setairportpower "$wifi_if" off 2>/dev/null || true
  sleep 2
  networksetup -setairportpower "$wifi_if" on 2>/dev/null || true

  echo
  echo "${GREEN}Wi-Fi fix complete. Connection should re-establish in a few seconds.${RESET}"
}
