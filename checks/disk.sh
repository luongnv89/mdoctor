#!/usr/bin/env bash
#
# checks/disk.sh
# Disk health and free space checks
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
check_disk() {
  step "Disk health & free space"

  local used_pct
  local used_rc=0
  used_pct=$(disk_used_pct_root) || used_rc=$?
  if [ "$used_rc" -ne 0 ] || [ -z "$used_pct" ]; then
    status_warn "Disk usage: could not determine"
    return 0
  fi

  status_info "Root filesystem usage: ${used_pct}%"
  # _disk_root_init + _MDOCTOR_DISK_ROOT skips the $(_disk_root) subshell
  # (issue #98); the df table is re-indented in-shell, first two rows
  # only like the retired awk 'NR==1 || NR==2'.
  _disk_root_init
  local _dfn=0 _dfl
  df -h "$_MDOCTOR_DISK_ROOT" | while IFS= read -r _dfl; do
    _dfn=$((_dfn + 1))
    if (( _dfn > 2 )); then
      break
    fi
    printf '  %s\n' "$_dfl"
  done

  if (( used_pct >= 90 )); then
    status_fail "Disk is almost full (>= 90%)."
    add_action "Free disk space on / (currently ${used_pct}% used): delete large files, clean caches, or move archives to external storage."
  elif (( used_pct >= 80 )); then
    status_warn "Disk is getting full (>= 80%)."
    add_action "Plan to free space on / soon (currently ${used_pct}% used)."
  else
    status_ok "Disk usage is within a healthy range."
  fi
}
