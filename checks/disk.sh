#!/usr/bin/env bash
#
# checks/disk.sh
# Disk health and free space checks
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
check_disk() {
  step "Disk health & free space"

  local used_pct
  used_pct=$(disk_used_pct_root)

  status_info "Root filesystem usage: ${used_pct}%"
  df -h "$(_disk_root)" | awk 'NR==1 || NR==2 {print "  "$0}'

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
