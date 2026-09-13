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
  if [ "$used_rc" -eq "$MDOCTOR_SIZE_ERR_TIMEOUT" ]; then
    status_info "Disk usage: timed out (timeout ${MDOCTOR_CMD_TIMEOUT_S}s) — df did not answer."
    return 0
  fi
  # is_uint gate (issue #111): a non-numeric reading must report "could
  # not determine" — never reach the (( )) thresholds below, where it
  # would coerce to 0 and a full disk would report healthy.
  if [ "$used_rc" -ne 0 ] || ! is_uint "$used_pct"; then
    status_warn "Disk usage: could not determine"
    return 0
  fi

  status_info "Root filesystem usage: ${used_pct}%"
  # _disk_root_init + _MDOCTOR_DISK_ROOT skips the $(_disk_root) subshell
  # (issue #98); the df table is re-indented in-shell, first two rows
  # only like the retired awk 'NR==1 || NR==2'.
  _disk_root_init
  local _dfn=0 _dfl _df_out="" _df_rc=0
  # df is timeout-capped (issue #101): a stale NFS mount can wedge df;
  # capture first so the pipeline's 124 isn't swallowed by the loop.
  _df_out=$(mdoctor_timeout "$MDOCTOR_CMD_TIMEOUT_S" df -h "$_MDOCTOR_DISK_ROOT" 2>/dev/null) || _df_rc=$?
  if [ "$_df_rc" -eq 124 ]; then
    status_info "df table: timed out (timeout ${MDOCTOR_CMD_TIMEOUT_S}s) — mount table unavailable."
  else
    while IFS= read -r _dfl; do
      _dfn=$((_dfn + 1))
      if (( _dfn > 2 )); then
        break
      fi
      printf '  %s\n' "$_dfl"
    done <<< "$_df_out"
  fi

  if (( 10#$used_pct >= 90 )); then
    status_fail "Disk is almost full (>= 90%)."
    add_action "Free disk space on / (currently ${used_pct}% used): delete large files, clean caches, or move archives to external storage."
  elif (( 10#$used_pct >= 80 )); then
    status_warn "Disk is getting full (>= 80%)."
    add_action "Plan to free space on / soon (currently ${used_pct}% used)."
  else
    status_ok "Disk usage is within a healthy range."
  fi
}
