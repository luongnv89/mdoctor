#!/usr/bin/env bash
#
# checks/pacman.sh
# Pacman package manager health (read-only, SAFE)
# Category: Software
# Platform: Linux (Arch-family, including Omarchy) only
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
check_pacman() {
  step "Pacman Package Manager"

  if ! command -v pacman >/dev/null 2>&1; then
    status_info "Pacman not available on this system."
    return 0
  fi

  # Installed package count — local db read, still timeout-capped with a
  # distinct "timed out" report (issue #101). Counted in-shell (issue #98
  # convention): a printf|wc pipe mis-counts empty captures.
  local installed_count=0 _q_rc=0
  tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "pacman -Q probe" pacman -Q || _q_rc=$?
  if [ "$_q_rc" -ne 124 ]; then
    local _qline
    while IFS= read -r _qline; do
      [ -n "$_qline" ] && installed_count=$((installed_count + 1))
    done <<< "$_TCAP_OUT"
    status_info "Installed packages: ${installed_count}"
  fi

  # Pending updates — same probe checks/updates.sh runs; repeated here so
  # the single-module path (`check -m pacman`) reports it on its own.
  local upgradable=0 _pq_rc=0
  tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "pacman -Qu probe" pacman -Qu || _pq_rc=$?
  if [ "$_pq_rc" -ne 124 ]; then
    local _pqline
    while IFS= read -r _pqline; do
      [ -n "$_pqline" ] && upgradable=$((upgradable + 1))
    done <<< "$_TCAP_OUT"
    if (( upgradable > 0 )); then
      status_warn "${upgradable} package update(s) available"
      add_action "Run 'sudo pacman -Syu' to apply pending updates."
    else
      status_ok "All packages are up to date."
    fi
  fi

  # Orphan packages (installed as dependencies, no longer required).
  local orphan_count=0 _oq_rc=0
  tcap "$MDOCTOR_CMD_TIMEOUT_S" "pacman orphan probe" pacman -Qtdq || _oq_rc=$?
  if [ "$_oq_rc" -ne 124 ]; then
    local _oqline
    while IFS= read -r _oqline; do
      [ -n "$_oqline" ] && orphan_count=$((orphan_count + 1))
    done <<< "$_TCAP_OUT"
    if (( orphan_count > 0 )); then
      status_info "Orphan packages: ${orphan_count}"
      add_action "Remove orphan packages: sudo pacman -Rns \$(pacman -Qtdq)"
    fi
  fi

  # Pacman cache size.
  local cache_size cache_size_raw cache_size_rc=0
  cache_size_raw=$(du_size_kb /var/cache/pacman/pkg) || cache_size_rc=$?
  if [ "$cache_size_rc" -ne 0 ]; then
    status_info "Pacman cache size: could not determine"
  else
    cache_size=$(to_int "$cache_size_raw")
    if (( cache_size > 524288 )); then  # > 512 MB
      local cache_hr
      cache_hr=$(kb_to_human "$cache_size")
      status_info "Pacman cache size: ${cache_hr}"
      add_action "Clean pacman cache: sudo paccache -r && sudo pacman -Sc"
    fi
  fi

  # .pacnew/.pacsave files — config updates pacman refused to merge.
  local pacnew_count=0 _pn_out="" _pn_rc=0
  _pn_out=$(mdoctor_timeout "$MDOCTOR_CMD_TIMEOUT_S" find /etc -name '*.pacnew' -o -name '*.pacsave' 2>/dev/null) || _pn_rc=$?
  if [ "$_pn_rc" -ne 124 ] && [ -n "$_pn_out" ]; then
    local _pnline
    while IFS= read -r _pnline; do
      [ -n "$_pnline" ] && pacnew_count=$((pacnew_count + 1))
    done <<< "$_pn_out"
    if (( pacnew_count > 0 )); then
      status_warn "${pacnew_count} unmerged .pacnew/.pacsave file(s) under /etc"
      add_action "Review unmerged configs with 'pacdiff' (pacman-contrib) and merge them."
    fi
  fi
}
