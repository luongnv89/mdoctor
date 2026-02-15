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
# SPINNER / PROGRESS BAR
########################################

SPINNER_PID=""
_PROGRESS_LABEL=""

progress_start() {
  # Skip spinner if not a terminal or no label
  [ -t 1 ] || return 0
  [ -n "${1:-}" ] || return 0

  local label="$1"
  _PROGRESS_LABEL="$label"
  local current="${STEP_CURRENT:-0}"
  local total="${STEP_TOTAL:-1}"

  (
    # Trap SIGTERM so the subshell exits cleanly without "Terminated" noise
    trap 'exit 0' TERM

    local frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local bar_width=20
    local i=0

    # Compute filled portion
    local filled=0
    if [ "$total" -gt 0 ]; then
      filled=$(( current * bar_width / total ))
    fi
    local empty=$(( bar_width - filled ))
    local pct=$(( current * 100 / (total > 0 ? total : 1) ))

    # Build bar string once (it doesn't change within a step)
    local bar=""
    local j=0
    while [ "$j" -lt "$filled" ]; do
      bar="${bar}█"
      j=$((j + 1))
    done
    j=0
    while [ "$j" -lt "$empty" ]; do
      bar="${bar}░"
      j=$((j + 1))
    done

    # Erase-to-EOL sequence
    local el=""
    if command -v tput >/dev/null 2>&1; then
      el="$(tput el 2>/dev/null || true)"
    fi

    while true; do
      local frame_char="${frames:$((i % 10)):1}"
      printf "\r  %s [%s] %3d%% %s%s" "$frame_char" "$bar" "$pct" "$label" "$el" 2>/dev/null
      i=$((i + 1))
      sleep 0.1
    done
  ) &

  SPINNER_PID=$!
  # Ensure spinner is cleaned up on script exit
  trap 'progress_stop' EXIT
}

progress_stop() {
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    # Clear the spinner line if stdout is a terminal
    if [ -t 1 ]; then
      local el=""
      if command -v tput >/dev/null 2>&1; then
        el="$(tput el 2>/dev/null || true)"
      fi
      printf "\r%s" "$el" 2>/dev/null
    fi
  fi
}

########################################
# UI HELPERS
########################################

step() {
  progress_stop

  STEP_CURRENT=$((STEP_CURRENT + 1))
  local title="$1"
  echo
  echo "${BOLD}➤ [${STEP_CURRENT}/${STEP_TOTAL}] ${title}${RESET}"
  echo "----------------------------------------"

  md_append ""
  md_append "## [${STEP_CURRENT}/${STEP_TOTAL}] ${title}"
  md_append ""

  progress_start "$title"
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
  progress_stop
  echo "  ${CHECK} ${GREEN}${msg}${RESET}"
  md_append "- ✅ ${msg}"
  progress_start "${_PROGRESS_LABEL:-}"
}

status_warn() {
  local msg="$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  progress_stop
  echo "  ${WARN} ${YELLOW}${msg}${RESET}"
  md_append "- ⚠️ ${msg}"
  progress_start "${_PROGRESS_LABEL:-}"
}

status_fail() {
  local msg="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  progress_stop
  echo "  ${CROSS} ${RED}${msg}${RESET}"
  md_append "- ❌ ${msg}"
  progress_start "${_PROGRESS_LABEL:-}"
}

status_info() {
  local msg="$1"
  progress_stop
  echo "  ${INFO} ${msg}"
  md_append "- ℹ️ ${msg}"
  progress_start "${_PROGRESS_LABEL:-}"
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
