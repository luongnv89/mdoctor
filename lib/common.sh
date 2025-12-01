#!/usr/bin/env bash
#
# lib/common.sh
# Common utilities: colors, icons, UI helpers
#

########################################
# COLORS & ICONS
########################################

init_colors() {
  if command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
  else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
  fi

  CHECK="✅"
  WARN="⚠️"
  CROSS="❌"
  INFO="ℹ️"
}

########################################
# UI HELPERS
########################################

step() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  local title="$1"
  echo
  echo "${BOLD}➤ [${STEP_CURRENT}/${STEP_TOTAL}] ${title}${RESET}"
  echo "----------------------------------------"

  md_append ""
  md_append "## [${STEP_CURRENT}/${STEP_TOTAL}] ${title}"
  md_append ""
}

section_title() {
  local title="$1"
  echo
  echo "${BOLD}${BLUE}== ${title} ==${RESET}"

  md_append ""
  md_append "## ${title}"
  md_append ""
}

status_ok() {
  local msg="$1"
  echo "  ${CHECK} ${GREEN}${msg}${RESET}"
  md_append "- ✅ ${msg}"
}

status_warn() {
  local msg="$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  echo "  ${WARN} ${YELLOW}${msg}${RESET}"
  md_append "- ⚠️ ${msg}"
}

status_fail() {
  local msg="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  ${CROSS} ${RED}${msg}${RESET}"
  md_append "- ❌ ${msg}"
}

status_info() {
  local msg="$1"
  echo "  ${INFO} ${msg}"
  md_append "- ℹ️ ${msg}"
}

add_action() {
  local msg="${1-}"
  [ -n "${msg}" ] && ACTIONS+=("$msg")
}

add_log_file() {
  local path="${1-}"
  local desc="${2-}"
  if [ -n "${path}" ]; then
    LOG_PATHS+=("$path")
    LOG_DESCS+=("$desc")
  fi
}
