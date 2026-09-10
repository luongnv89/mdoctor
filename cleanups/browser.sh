#!/usr/bin/env bash
#
# cleanups/browser.sh
# Browser caches cleanup (optional)
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_browser_caches() {
  local rc=0
  header "Cleaning browser caches"

  if is_macos; then
    # Google Chrome
    if [ -d "${HOME}/Library/Caches/Google/Chrome" ]; then
      safe_remove_children "${HOME}/Library/Caches/Google/Chrome" || rc=$?
    fi
    # Safari
    if [ -d "${HOME}/Library/Caches/com.apple.Safari" ]; then
      safe_remove_children "${HOME}/Library/Caches/com.apple.Safari" || rc=$?
    fi
    # Firefox
    if [ -d "${HOME}/Library/Caches/Firefox" ]; then
      safe_remove_children "${HOME}/Library/Caches/Firefox" || rc=$?
    fi
  else
    # Linux: XDG cache paths
    local chrome_cache="${HOME}/.cache/google-chrome"
    if [ -d "$chrome_cache" ]; then
      safe_remove_children "$chrome_cache" || rc=$?
    fi
    local chromium_cache="${HOME}/.cache/chromium"
    if [ -d "$chromium_cache" ]; then
      safe_remove_children "$chromium_cache" || rc=$?
    fi
    local firefox_cache="${HOME}/.cache/mozilla/firefox"
    if [ -d "$firefox_cache" ]; then
      safe_remove_children "$firefox_cache" || rc=$?
    fi
  fi
  handle_cleanup_rc "$rc" || rc=$?
  [ "$rc" -eq 0 ] || log "Module 'browser' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'browser')"
  return "$rc"
}
