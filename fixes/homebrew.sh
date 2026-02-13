#!/usr/bin/env bash
#
# fixes/homebrew.sh
# Fix Homebrew issues: update, upgrade, cleanup, doctor
# Risk: LOW
#

fix_homebrew() {
  echo "${BOLD}${BLUE}== Fixing Homebrew ==${RESET}"
  echo

  if ! command -v brew >/dev/null 2>&1; then
    echo "${RED}Error:${RESET} Homebrew is not installed." >&2
    echo "Install it with: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    return 1
  fi

  echo "${CYAN}[1/4]${RESET} Updating Homebrew..."
  brew update

  echo "${CYAN}[2/4]${RESET} Upgrading outdated packages..."
  brew upgrade

  echo "${CYAN}[3/4]${RESET} Cleaning up old versions..."
  brew cleanup -s
  brew autoremove

  echo "${CYAN}[4/4]${RESET} Running brew doctor..."
  brew doctor || true

  echo
  echo "${GREEN}Homebrew fixes complete.${RESET}"
}
