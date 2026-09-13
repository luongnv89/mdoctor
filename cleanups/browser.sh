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
# _browser_running PROC — rc 0 when pgrep finds a process named PROC.
# A missing pgrep fails open (rc 1): the running-browser guard is
# best-effort, and tests stub pgrep on PATH (issue #112).
_browser_running() {
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -x "$1" >/dev/null 2>&1
}

# _clean_browser_cache LABEL DIR PROC — delete DIR's children unless
# pgrep finds PROC running. Deleting cache index/journal files under a
# live browser corrupts the cache (issue #112), so the skip happens
# BEFORE the safety call and is logged.
_clean_browser_cache() {
  local label="$1"
  local dir="$2"
  local proc="$3"
  [ -d "$dir" ] || return 0
  if _browser_running "$proc"; then
    log "Skipping ${label} cache (${dir}): ${proc} is running."
    return 0
  fi
  safe_remove_children "$dir"
}

clean_browser_caches() {
  local rc=0
  header "Cleaning browser caches"

  if is_macos; then
    # Google Chrome
    _clean_browser_cache "Chrome" "${HOME}/Library/Caches/Google/Chrome" "Google Chrome" || rc=$?
    # Safari
    _clean_browser_cache "Safari" "${HOME}/Library/Caches/com.apple.Safari" "Safari" || rc=$?
    # Firefox
    _clean_browser_cache "Firefox" "${HOME}/Library/Caches/Firefox" "firefox" || rc=$?
  else
    # Linux: XDG cache paths
    _clean_browser_cache "google-chrome" "${HOME}/.cache/google-chrome" "chrome" || rc=$?
    _clean_browser_cache "chromium" "${HOME}/.cache/chromium" "chromium" || rc=$?
    _clean_browser_cache "firefox" "${HOME}/.cache/mozilla/firefox" "firefox" || rc=$?
  fi
  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'browser' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'browser')"
  return "$rc"
}
