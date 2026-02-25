#!/usr/bin/env bash
#
# fixes/apt.sh
# APT package manager fix
# Risk: LOW
# Platform: Linux (Debian-family) only
#

fix_apt() {
  echo "${BOLD}${BLUE}== APT Package Manager Fix ==${RESET}"
  echo

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "APT not available on this system."
    return 1
  fi

  echo "Updating package lists..."
  sudo apt-get update

  echo "Fixing broken packages..."
  sudo dpkg --configure -a 2>/dev/null || true
  sudo apt-get --fix-broken install -y

  echo "Upgrading packages..."
  sudo apt-get upgrade -y

  echo "Removing unused packages..."
  sudo apt-get autoremove -y

  echo "Cleaning package cache..."
  sudo apt-get clean

  echo
  echo "${GREEN}APT package manager fix complete.${RESET}"
}
