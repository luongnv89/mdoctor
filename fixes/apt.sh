#!/usr/bin/env bash
#
# fixes/apt.sh
# APT package manager fix
# Risk: LOW
# Platform: Linux (Debian-family) only
#

fix_apt() {
  header "APT Package Manager Fix"

  local step_rc=0

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "APT not available on this system."
    return 1
  fi

  echo "Updating package lists..."
  run_cmd_args sudo apt-get update || step_rc=$?

  echo "Fixing broken packages..."
  run_cmd_args sudo dpkg --configure -a 2>/dev/null || step_rc=$?
  run_cmd_args sudo apt-get --fix-broken install -y || step_rc=$?

  echo "Upgrading packages..."
  run_cmd_args sudo apt-get upgrade -y || step_rc=$?

  echo "Removing unused packages..."
  run_cmd_args sudo apt-get autoremove -y || step_rc=$?

  echo "Cleaning package cache..."
  run_cmd_args sudo apt-get clean || step_rc=$?

  echo
  if [ "$step_rc" -eq 0 ]; then
    status_ok "APT package manager fix complete."
    return 0
  else
    status_warn "APT fix reported errors (see above)."
    return 1
  fi
}
