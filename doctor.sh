#!/usr/bin/env bash
#
# doctor.sh
# macOS health & dev-environment audit script (read-only) with health score,
# package/module update hints, and a Markdown report output.
#
# Usage:
#   ./doctor.sh
#

set -uo pipefail

########################################
# SCRIPT DIRECTORY & MODULE LOADING
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/disk.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/lib/metadata.sh"
source "${SCRIPT_DIR}/lib/history.sh"

# Source check modules — Hardware
source "${SCRIPT_DIR}/checks/battery.sh"
source "${SCRIPT_DIR}/checks/hardware.sh"
source "${SCRIPT_DIR}/checks/bluetooth.sh"
source "${SCRIPT_DIR}/checks/usb.sh"

# Source check modules — System (existing + new)
source "${SCRIPT_DIR}/checks/system.sh"
source "${SCRIPT_DIR}/checks/disk.sh"
source "${SCRIPT_DIR}/checks/updates.sh"
source "${SCRIPT_DIR}/checks/security.sh"
source "${SCRIPT_DIR}/checks/startup.sh"
source "${SCRIPT_DIR}/checks/network.sh"
source "${SCRIPT_DIR}/checks/performance.sh"
source "${SCRIPT_DIR}/checks/storage.sh"

# Source check modules — Software (existing + new)
source "${SCRIPT_DIR}/checks/homebrew.sh"
source "${SCRIPT_DIR}/checks/node.sh"
source "${SCRIPT_DIR}/checks/python.sh"
source "${SCRIPT_DIR}/checks/devtools.sh"
source "${SCRIPT_DIR}/checks/shell.sh"
source "${SCRIPT_DIR}/checks/apps.sh"
source "${SCRIPT_DIR}/checks/git_config.sh"
source "${SCRIPT_DIR}/checks/containers.sh"

########################################
# MODULE REGISTRATION
########################################

# Hardware checks
register_module check battery   Hardware SAFE check_battery     "Battery health, cycle count, capacity"
register_module check hardware  Hardware SAFE check_hardware    "CPU, RAM, model, thermals"
register_module check bluetooth Hardware SAFE check_bluetooth   "Bluetooth power state & devices"
register_module check usb       Hardware SAFE check_usb         "Connected USB devices"

# System checks
register_module check system      System SAFE check_system        "OS version, memory, load average"
register_module check disk        System SAFE check_disk          "Disk usage & health"
register_module check updates     System SAFE check_updates_basic "macOS updates & Spotlight"
register_module check security    System SAFE check_security      "Firewall, FileVault, SIP, Gatekeeper"
register_module check startup     System SAFE check_startup       "Launch agents, daemons, login items"
register_module check network     System SAFE check_network       "Connectivity, DNS, Wi-Fi signal"
register_module check performance System SAFE check_performance   "Memory pressure, CPU, processes"
register_module check storage     System SAFE check_storage       "Large files & app storage analysis"

# Software checks
register_module check homebrew   Software SAFE check_homebrew    "Homebrew installation & packages"
register_module check node       Software SAFE check_node_npm    "Node.js & npm"
register_module check python     Software SAFE check_python      "Python & pip"
register_module check devtools   Software SAFE check_dev_tools   "Xcode CLT, Git, Docker"
register_module check shell      Software SAFE check_shell_configs "Shell config syntax"
register_module check apps       Software SAFE check_apps        "Crash reports, application health"
register_module check git_config Software SAFE check_git_config  "Git & SSH configuration"
register_module check containers Software SAFE check_containers  "Docker & container health"

########################################
# GLOBAL STATE
########################################

# shellcheck disable=SC2034
STEP_CURRENT=0
# shellcheck disable=SC2034
STEP_TOTAL=21  # 4 hardware + 8 system + 9 software

ACTIONS=()
# shellcheck disable=SC2034
WARN_COUNT=0
# shellcheck disable=SC2034
FAIL_COUNT=0

# shellcheck disable=SC2034
LOG_PATHS=()
# shellcheck disable=SC2034
LOG_DESCS=()

REPORT_MD=""

########################################
# MAIN
########################################

main() {
  # Initialize colors and UI
  init_colors
  debug_log "doctor.sh start json=${JSON_ENABLED:-false}"

  # Initialize markdown report
  md_init

  section_title "macOS Doctor – Full System Health Audit"
  echo "${INFO} This script is read-only: it does NOT change anything, only reports status."
  md_append "- ℹ️ This script is read-only: it does **not** modify your system."
  echo

  # Hardware checks
  debug_log "doctor.sh phase=hardware checks=4"
  check_battery
  check_hardware
  check_bluetooth
  check_usb

  # System checks
  debug_log "doctor.sh phase=system checks=8"
  check_system
  check_disk
  check_updates_basic
  check_security
  check_startup
  check_network
  check_performance
  check_storage

  # Software checks
  debug_log "doctor.sh phase=software checks=9"
  check_homebrew
  check_node_npm
  check_python
  check_dev_tools
  check_shell_configs
  check_apps
  check_git_config
  check_containers

  # Stop spinner from last check step
  progress_stop

  # Summary
  echo
  section_title "Summary"

  local MAX_SCORE=100
  local penalty
  local score
  penalty=$(( WARN_COUNT * 4 + FAIL_COUNT * 8 ))
  score=$(( MAX_SCORE - penalty ))
  if (( score < 0 )); then
    score=0
  fi

  local rating
  if (( score >= 90 )); then
    rating="Excellent"
  elif (( score >= 75 )); then
    rating="Good"
  elif (( score >= 50 )); then
    rating="Needs attention"
  else
    rating="Critical – fix issues ASAP"
  fi

  echo "Health score: ${BOLD}${score}/100${RESET} (${rating})"
  echo "Warnings: ${WARN_COUNT}, Failures: ${FAIL_COUNT}"
  debug_log "doctor.sh summary score=${score} rating=${rating} warnings=${WARN_COUNT} failures=${FAIL_COUNT}"
  echo

  md_append ""
  md_append "## Summary"
  md_append ""
  md_append "- Health score: **${score}/100** (${rating})"
  md_append "- Warnings: **${WARN_COUNT}**, Failures: **${FAIL_COUNT}**"
  md_append ""

  # JSON output: accumulate actions
  if [ "${JSON_ENABLED:-false}" = true ]; then
    local action
    for action in "${ACTIONS[@]}"; do
      json_add_action "$action"
    done
    json_build_output "$score" "$rating" "$WARN_COUNT" "$FAIL_COUNT"
  fi

  # Save history
  history_save "$score" "$rating" "$WARN_COUNT" "$FAIL_COUNT"

  # Actionable next steps
  if ((${#ACTIONS[@]} > 0)); then
    echo "${BOLD}Actionable next steps:${RESET}"
    md_append "### Actionable next steps"
    md_append ""
    local i=1
    for action in "${ACTIONS[@]}"; do
      echo "  ${i}. ${action}"
      md_append "${i}. ${action}"
      i=$((i + 1))
    done
  else
    local msg="No immediate actions detected. Your system/dev setup looks healthy."
    echo "  ${CHECK} ${GREEN}${msg}${RESET}"
    md_append "### Actionable next steps"
    md_append ""
    md_append "- ✅ ${msg}"
  fi

  # Log files
  if ((${#LOG_PATHS[@]} > 0)); then
    echo
    echo "${BOLD}Detailed logs generated in this run:${RESET}"
    md_append ""
    md_append "### Detailed logs"
    md_append ""
    local j=0
    local n=${#LOG_PATHS[@]}
    while (( j < n )); do
      local p="${LOG_PATHS[$j]}"
      local d="${LOG_DESCS[$j]}"
      if [ -f "$p" ]; then
        printf "  %-32s # %s\n" "$p" "$d"
        md_append "- \`$p\` — ${d}"
      fi
      j=$((j + 1))
    done
  fi

  echo
  echo "${BOLD}Markdown report saved to:${RESET} ${REPORT_MD}"
  echo
  echo "${BOLD}Done.${RESET}"
  md_append ""
  md_append "_End of report._"
}

main "$@"
