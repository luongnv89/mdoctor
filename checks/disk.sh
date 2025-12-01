#!/usr/bin/env bash
#
# checks/disk.sh
# Disk health and free space checks
#

check_disk() {
  step "Disk health & free space"

  local used_pct
  used_pct=$(disk_used_pct_root)

  status_info "Root filesystem usage: ${used_pct}%"
  df -h / | awk 'NR==1 || NR==2 {print "  "$0}'

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
