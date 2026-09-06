#!/usr/bin/env bash
#
# fixes/permissions.sh
# Reset Homebrew and /usr/local permissions (macOS only)
# Risk: MED
#

fix_permissions() {
  echo "${BOLD}${BLUE}== Resetting Permissions ==${RESET}"
  echo

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
  if sudo chown -R "$(whoami)" "${brew_prefix}/share" "${brew_prefix}/lib" "${brew_prefix}/Cellar" 2>/dev/null; then
    echo "${GREEN}Homebrew permissions reset.${RESET}"
  else
    echo "${RED}Failed to reset Homebrew permissions.${RESET}" >&2
    return 1
  fi

  echo "Resetting /usr/local permissions..."
  if sudo chown -R "$(whoami)" /usr/local 2>/dev/null; then
    echo "${GREEN}Permissions reset complete.${RESET}"
  else
    echo "${RED}Failed to reset /usr/local permissions.${RESET}" >&2
    return 1
  fi
}
