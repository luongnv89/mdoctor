#!/usr/bin/env bash
#
# cleanups/apt.sh
# APT package cache cleanup
# Risk: LOW
# Platform: Linux (Debian-family) only
#

clean_apt_cache() {
  header "APT cache cleanup"

  if ! command -v apt-get >/dev/null 2>&1; then
    log "APT not available; skipping."
    return 0
  fi

  # Clean downloaded .deb files
  log "Cleaning APT package cache..."
  run_cmd_args sudo apt-get clean

  # Remove old partial downloads
  run_cmd_args sudo apt-get autoclean

  # Remove auto-installed packages no longer needed
  log "Removing unused auto-installed packages..."
  run_cmd_args sudo apt-get autoremove -y
}
