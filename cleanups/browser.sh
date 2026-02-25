#!/usr/bin/env bash
#
# cleanups/browser.sh
# Browser caches cleanup (optional)
#

clean_browser_caches() {
  header "Cleaning browser caches"

  if is_macos; then
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
  else
    # Linux: XDG cache paths
    local chrome_cache="${HOME}/.cache/google-chrome"
    if [ -d "$chrome_cache" ]; then
      safe_remove_children "$chrome_cache" || true
    fi
    local chromium_cache="${HOME}/.cache/chromium"
    if [ -d "$chromium_cache" ]; then
      safe_remove_children "$chromium_cache" || true
    fi
    local firefox_cache="${HOME}/.cache/mozilla/firefox"
    if [ -d "$firefox_cache" ]; then
      safe_remove_children "$firefox_cache" || true
    fi
  fi
}
