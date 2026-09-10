#!/usr/bin/env bash
#
# fixes/wifi.sh
# 3-step Wi-Fi fix: renew DHCP, flush DNS, cycle Wi-Fi
# Risk: LOW
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required fixes inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
fix_wifi() {
  header "Fixing Wi-Fi"

  if ! is_macos; then
    echo "${YELLOW}Wi-Fi fix is macOS-only (networksetup/ipconfig) — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  # Detect active Wi-Fi interface (read-only probe)
  local wifi_if
  wifi_if=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2}')
  if [ -z "$wifi_if" ]; then
    # Fallback: try en0 (common default)
    wifi_if="en0"
  fi

  echo "Detected Wi-Fi interface: ${wifi_if}"
  echo

  local step_rc=0

  echo "${CYAN}[1/3]${RESET} Renewing DHCP lease..."
  run_cmd_args sudo ipconfig set "$wifi_if" DHCP 2>/dev/null || step_rc=$?

  echo "${CYAN}[2/3]${RESET} Flushing DNS cache..."
  run_cmd_args sudo dscacheutil -flushcache 2>/dev/null || step_rc=$?
  run_cmd_args sudo killall -HUP mDNSResponder 2>/dev/null || step_rc=$?

  echo "${CYAN}[3/3]${RESET} Cycling Wi-Fi off/on..."
  run_cmd_args networksetup -setairportpower "$wifi_if" off 2>/dev/null || step_rc=$?
  sleep 2
  run_cmd_args networksetup -setairportpower "$wifi_if" on 2>/dev/null || step_rc=$?

  echo
  if [ "$step_rc" -eq 0 ]; then
    status_ok "Wi-Fi fix complete. Connection should re-establish in a few seconds."
    return 0
  else
    status_warn "Wi-Fi fix reported errors (see above)."
    return 1
  fi
}
