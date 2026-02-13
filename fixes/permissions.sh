#!/usr/bin/env bash
#
# fixes/permissions.sh
# Reset Homebrew and /usr/local permissions
# Risk: MED
#

fix_permissions() {
  echo "${BOLD}${BLUE}== Resetting Permissions ==${RESET}"
  echo

  echo "Resetting Homebrew permissions..."
  if command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix="$(brew --prefix)"
    sudo chown -R "$(whoami)" "${brew_prefix}/share" "${brew_prefix}/lib" "${brew_prefix}/Cellar" 2>/dev/null || true
    echo "${GREEN}Homebrew permissions reset.${RESET}"
  else
    echo "${DIM}Homebrew not installed, skipping.${RESET}"
  fi

  echo "Resetting /usr/local permissions..."
  sudo chown -R "$(whoami)" /usr/local 2>/dev/null || true
  echo "${GREEN}Permissions reset complete.${RESET}"
}
