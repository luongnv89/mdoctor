#!/usr/bin/env bash
#
# cleanups/browser.sh
# Browser caches cleanup (optional)
#

clean_browser_caches() {
  header "Cleaning browser caches (optional; currently DISABLED)"

  # Google Chrome
  if [ -d "${HOME}/Library/Caches/Google/Chrome" ]; then
    safe_remove_children "${HOME}/Library/Caches/Google/Chrome" || true
  fi

  # Safari
  if [ -d "${HOME}/Library/Caches/com.apple.Safari" ]; then
    safe_remove_children "${HOME}/Library/Caches/com.apple.Safari" || true
  fi

  # Firefox
  if [ -d "${HOME}/Library/Caches/Firefox" ]; then
    safe_remove_children "${HOME}/Library/Caches/Firefox" || true
  fi
}
