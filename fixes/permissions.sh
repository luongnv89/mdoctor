#!/usr/bin/env bash
#
# fixes/permissions.sh
# Reset Homebrew and /usr/local permissions (macOS only)
# Risk: MED
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
fix_permissions() {
  header "Resetting Permissions"

  # Task 1.2: this module exists to repair Homebrew-owned trees. The
  # recursive /usr/local reassignment is a privilege-escalation setup on
  # Debian (secure_path), so nothing here runs unless BOTH guards hold.
  if ! is_macos; then
    echo "${DIM}permissions fix is macOS-only — skipping on $(platform_name).${RESET}"
    return 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "${DIM}Homebrew not installed, skipping.${RESET}"
    return 1
  fi

  echo "Resetting Homebrew permissions..."
  local brew_prefix
  brew_prefix="$(brew --prefix)"
  if ! run_cmd_args sudo chown -R "$(whoami)" "${brew_prefix}/share" "${brew_prefix}/lib" "${brew_prefix}/Cellar" 2>/dev/null; then
    status_fail "Failed to reset Homebrew permissions."
    return 1
  fi
  status_ok "Homebrew permissions reset."

  echo "Resetting /usr/local permissions..."
  if run_cmd_args sudo chown -R "$(whoami)" /usr/local 2>/dev/null; then
    status_ok "Permissions reset complete."
    return 0
  else
    status_fail "Failed to reset /usr/local permissions."
    return 1
  fi
}
