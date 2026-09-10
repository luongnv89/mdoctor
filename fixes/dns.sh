#!/usr/bin/env bash
#
# fixes/dns.sh
# Flush DNS cache
# Risk: LOW
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required fixes inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
fix_dns() {
  header "Flushing DNS Cache"

  local step_rc=0

  if is_macos; then
    echo "Flushing macOS DNS cache..."
    run_cmd_args sudo dscacheutil -flushcache 2>/dev/null || step_rc=$?
    run_cmd_args sudo killall -HUP mDNSResponder 2>/dev/null || step_rc=$?
  else
    echo "Flushing Linux DNS cache..."
    if command -v resolvectl >/dev/null 2>&1; then
      run_cmd_args sudo resolvectl flush-caches 2>/dev/null || step_rc=$?
    elif command -v systemd-resolve >/dev/null 2>&1; then
      run_cmd_args sudo systemd-resolve --flush-caches 2>/dev/null || step_rc=$?
    else
      echo "No systemd-resolved found. If using nscd: sudo systemctl restart nscd"
    fi
  fi

  if [ "$step_rc" -eq 0 ]; then
    status_ok "DNS cache flushed."
    return 0
  else
    status_warn "DNS flush reported errors (see above)."
    return 1
  fi
}
