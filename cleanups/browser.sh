#!/usr/bin/env bash
#
# cleanups/browser.sh
# Browser caches cleanup (optional)
#

clean_browser_caches() {
  header "Cleaning browser caches (optional; currently DISABLED)"

  # Google Chrome
  if [ -d "${HOME}/Library/Caches/Google/Chrome" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Google/Chrome\"/*"
  fi

  # Safari
  if [ -d "${HOME}/Library/Caches/com.apple.Safari" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/com.apple.Safari\"/*"
  fi

  # Firefox
  if [ -d "${HOME}/Library/Caches/Firefox" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Firefox\"/*"
  fi
}
