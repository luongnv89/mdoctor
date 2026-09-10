#!/usr/bin/env bash
#
# cleanups/apt.sh
# APT package cache cleanup
# Risk: LOW
# Platform: Linux (Debian-family) only
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
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
