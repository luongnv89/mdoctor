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

# Source check modules
source "${SCRIPT_DIR}/checks/system.sh"
source "${SCRIPT_DIR}/checks/disk.sh"
source "${SCRIPT_DIR}/checks/updates.sh"
source "${SCRIPT_DIR}/checks/homebrew.sh"
source "${SCRIPT_DIR}/checks/node.sh"
source "${SCRIPT_DIR}/checks/python.sh"
source "${SCRIPT_DIR}/checks/devtools.sh"
source "${SCRIPT_DIR}/checks/shell.sh"
source "${SCRIPT_DIR}/checks/network.sh"

########################################
# GLOBAL STATE
########################################

STEP_CURRENT=0
STEP_TOTAL=9  # update if you add/remove check modules

ACTIONS=()
WARN_COUNT=0
FAIL_COUNT=0

LOG_PATHS=()
LOG_DESCS=()

REPORT_MD=""

########################################
# MAIN
########################################

main() {
  # Initialize colors and UI
  init_colors

  # Initialize markdown report
  md_init

  section_title "macOS Doctor – System & Dev Environment Audit"
  echo "${INFO} This script is read-only: it does NOT change anything, only reports status."
  md_append "- ℹ️ This script is read-only: it does **not** modify your system."
  echo

  # Run all checks
  check_system
  check_disk
  check_updates_basic
  check_homebrew
  check_node_npm
  check_python
  check_dev_tools
  check_shell_configs
  check_network

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
  echo

  md_append ""
  md_append "## Summary"
  md_append ""
  md_append "- Health score: **${score}/100** (${rating})"
  md_append "- Warnings: **${WARN_COUNT}**, Failures: **${FAIL_COUNT}**"
  md_append ""

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
