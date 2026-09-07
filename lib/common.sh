#!/usr/bin/env bash
#
# lib/common.sh
# Common utilities: colors, icons, UI helpers
#

########################################
# COLORS & ICONS
########################################

# Guard against double-sourcing (lib/logging.sh and lib/safety.sh pull
# this file in when is_dry_run is otherwise unavailable).
if [ "${_MDOCTOR_COMMON_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_COMMON_LOADED=true

init_colors() {
  # Each tput is failure-proofed: without TERM (CI, minimal envs) tput
  # errors, and under `set -e` that would kill the caller silently.
  if command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    YELLOW="$(tput setaf 3 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"
    BOLD="$(tput bold 2>/dev/null || true)"
    RESET="$(tput sgr0 2>/dev/null || true)"
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

########################################
# DRY-RUN PREDICATE (Task 1.6)
########################################

# is_dry_run — central fail-closed dry-run predicate. Never compare
# $DRY_RUN to a literal again; call this instead.
#
# Return codes:
#   0 — dry-run ENABLED (unset/empty default, or truthy: true/1/yes/y
#       in any letter case, surrounding whitespace ignored)
#   1 — dry-run EXPLICITLY DISABLED (force): false/0/no/n, the ONLY
#       code that may proceed to deletion
#   2 — value INVALID: warns on stderr and dry-run stays enabled
#       (fail closed)
#
# Call sites MUST branch on rc==1 explicitly so invalid values fail
# closed (plain `if is_dry_run` would take the force branch on rc 2):
#
#   local _dry_rc=0
#   is_dry_run || _dry_rc=$?
#   if [ "$_dry_rc" -eq 1 ]; then
#     <force path — explicit opt-out only>
#   else
#     <dry path — default, truthy, and invalid values>
#   fi
#
# (The `||` keeps the call safe under `set -e`.)
is_dry_run() {
  local raw="${DRY_RUN:-true}"
  local norm="$raw"

  # Trim leading/trailing whitespace (Bash 3.2-safe; no extglob).
  norm="${norm#"${norm%%[![:space:]]*}"}"
  norm="${norm%"${norm##*[![:space:]]}"}"

  case "$norm" in
    ""|[tT][rR][uU][eE]|1|[yY][eE][sS]|[yY])
      return 0
      ;;
    [fF][aA][lL][sS][eE]|0|[nN][oO]|[nN])
      return 1
      ;;
    *)
      echo "warning: ignoring invalid DRY_RUN='${raw}' — failing closed to dry-run enabled" >&2
      return 2
      ;;
  esac
}

########################################
# SECURE TEMP FILES (Task 4.3)
########################################

# mdoctor_tmpdir — per-user scratch dir (${TMPDIR:-/tmp}/mdoctor-$UID),
# created mode 0700. All temp files live under it via mktemp below.
mdoctor_tmpdir() {
  local dir="${TMPDIR:-/tmp}/mdoctor-${UID}"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" 2>/dev/null || true
    chmod 700 "$dir" 2>/dev/null || true
  fi
  printf '%s' "$dir"
}

# mdoctor_mktemp_file PREFIX — secure temp file path (created empty).
mdoctor_mktemp_file() {
  mktemp "$(mdoctor_tmpdir)/${1:-tmp}.XXXXXX"
}

# mdoctor_mktemp_dir PREFIX — secure temp directory path (created).
mdoctor_mktemp_dir() {
  mktemp -d "$(mdoctor_tmpdir)/${1:-tmp}.XXXXXX"
}

########################################
# DESTRUCTIVE-EXECUTION CONFIRMATION GATE (Task 0.5)
########################################

# confirm_destructive_execution [context]
# Returns 0 when deletion may proceed, 1 otherwise. Behavior:
# - MDOCTOR_ASSUME_YES=true  -> proceed with no prompt (automation/CI).
# - otherwise a y/N prompt is read from stdin; only an explicit
#   y/Y/yes proceeds. Anything else (n, empty, EOF) aborts.
# - on a non-tty stdin without an affirmative answer the refusal names
#   MDOCTOR_ASSUME_YES, so `--force < /dev/null` fails with a pointer
#   instead of hanging or deleting.
confirm_destructive_execution() {
  local context="${1:-cleanup}"

  if [ "${MDOCTOR_ASSUME_YES:-false}" = true ]; then
    return 0
  fi

  local answer=""
  printf 'Proceed with deletion (%s)? [y/N] ' "$context" >&2
  IFS= read -r answer || answer=""

  case "$answer" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
  esac

  if [ ! -t 0 ]; then
    echo "Refusing --force on a non-tty without MDOCTOR_ASSUME_YES=true: no confirmation received, nothing was deleted." >&2
  else
    echo "Aborted: nothing was deleted." >&2
  fi
  return 1
}
