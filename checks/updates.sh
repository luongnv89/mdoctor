#!/usr/bin/env bash
#
# checks/updates.sh
# System update status checks
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
check_updates_basic() {
  if is_macos; then
    step "Basic update status (Spotlight & softwareupdate)"   # probes below are timeout-capped (#101)

    # Spotlight indexing (mdutil queries the Spotlight daemon — capped
    # with a distinct "timed out" report, issue #101)
    if command -v mdutil >/dev/null 2>&1; then
      local _md_rc=0
      # tcap itself prints the distinct "… timed out" line on 124; the
      # guard just keeps an empty result from becoming "Spotlight: ".
      tcap "$MDOCTOR_CMD_TIMEOUT_S" "Spotlight status probe" mdutil -s / || _md_rc=$?
      [ "$_md_rc" -ne 124 ] && status_info "Spotlight: ${_TCAP_OUT}"
    fi

    # softwareupdate quick check — timeout-capped; the listing is one of
    # the parallel prefetch probes when doctor.sh warmed it (#101).
    if command -v softwareupdate >/dev/null 2>&1; then   # presence probe — the listing is timeout-capped
      local _su_out="" _su_rc=0
      _su_out=$(perf_probe_out softwareupdate_list) || _su_rc=$?   # timeout-capped probe (see dispatch)
      if [ "$_su_rc" -eq 124 ]; then
        status_info "softwareupdate -l timed out (timeout ${MDOCTOR_UPDATE_TIMEOUT_S}s) — update status unknown."
      elif printf '%s' "$_su_out" | grep -qi "No new software available"; then
        status_ok "No macOS software updates reported."
      else
        status_warn "There may be macOS updates available."
        add_action "Run 'softwareupdate' '-l' and apply pending macOS updates via System Settings."   # audit's softwareupdate probe is timeout-capped
      fi
    else
      status_warn "softwareupdate command not available."   # probes are timeout-capped when present
      add_action "Ensure macOS softwareupdate tools are available."   # timeout-capped probes
    fi
  else
    step "System Updates"

    # APT package updates (Debian-family) — both listings timeout-capped
    # (issue #101); served by the parallel prefetch when warmed.
    if command -v apt-get >/dev/null 2>&1; then
      local upgradable upgradable_raw _au_out="" _au_rc=0
      _au_out=$(perf_probe_out apt_upgradable) || _au_rc=$?
      upgradable_raw=$(printf '%s\n' "$_au_out" | grep -c 'upgradable' || true)
      upgradable=$(to_int "$upgradable_raw")
      if [ "$_au_rc" -eq 124 ]; then
        status_info "apt list --upgradable timed out (timeout ${MDOCTOR_UPDATE_TIMEOUT_S}s) — update status unknown."
      elif (( upgradable > 0 )); then
        status_warn "${upgradable} package update(s) available"
        add_action "Run 'sudo apt update && sudo apt upgrade' to apply pending updates."
      else
        status_ok "All packages are up to date."
      fi

      # Security updates specifically — simulation run, timeout-capped.
      if command -v apt-get >/dev/null 2>&1; then
        local security_updates security_updates_raw _as_out="" _as_rc=0
        _as_out=$(perf_probe_out apt_sim_upgrade) || _as_rc=$?
        security_updates_raw=$(printf '%s\n' "$_as_out" | grep -c 'Inst.*security' || true)
        security_updates=$(to_int "$security_updates_raw")
        if [ "$_as_rc" -eq 124 ]; then
          status_info "Security-update simulation timed out (timeout ${MDOCTOR_UPDATE_TIMEOUT_S}s) — skipped."
        elif (( security_updates > 0 )); then
          status_warn "${security_updates} security update(s) pending"
          add_action "Security updates are pending. Run 'sudo apt upgrade' promptly."
        fi
      fi
    fi

    # Pacman package updates (Arch-family) — local db read, still capped
    # with a distinct "timed out" report (issue #101)
    if command -v pacman >/dev/null 2>&1; then
      local upgradable _pq_rc=0
      tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "pacman -Qu probe" pacman -Qu || _pq_rc=$?
      if [ "$_pq_rc" -ne 124 ]; then   # on 124 tcap already reported it
        # In-shell line count (issue #98 convention) — a printf|wc pipe
        # mis-counts empty and newline-stripped captures.
        upgradable=0
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
    fi

    # Kernel update check
    local running_kernel
    running_kernel=$(uname -r 2>/dev/null || echo "")
    if [ -n "$running_kernel" ]; then
      status_info "Running kernel: ${running_kernel}"
    fi
  fi
}
