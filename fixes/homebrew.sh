#!/usr/bin/env bash
#
# fixes/homebrew.sh
# Fix Homebrew issues: update, upgrade, cleanup, doctor
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
fix_homebrew() {
  header "Fixing Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    status_fail "Homebrew is not installed."
    echo "Install it with: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    return 1
  fi

  local step_rc=0

  echo "${CYAN}[1/4]${RESET} Updating Homebrew..."
  run_cmd_args brew update || step_rc=$?

  echo "${CYAN}[2/4]${RESET} Upgrading outdated packages..."
  run_cmd_args brew upgrade || step_rc=$?

  echo "${CYAN}[3/4]${RESET} Cleaning up old versions..."
  run_cmd_args brew cleanup -s || step_rc=$?
  run_cmd_args brew autoremove || step_rc=$?

  echo "${CYAN}[4/4]${RESET} Running brew doctor..."
  run_cmd_args brew doctor || step_rc=$?

  echo
  if [ "$step_rc" -eq 0 ]; then
    status_ok "Homebrew fixes complete."
    return 0
  else
    status_warn "Homebrew fixes reported errors (see above)."
    return 1
  fi
}
