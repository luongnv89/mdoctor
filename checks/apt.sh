#!/usr/bin/env bash
#
# checks/apt.sh
# APT package manager health (read-only, SAFE)
# Category: Software
# Platform: Linux (Debian-family) only
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
check_apt() {
  step "APT Package Manager"

  if ! command -v apt-get >/dev/null 2>&1; then
    status_info "APT not available on this system."
    return 0
  fi

  # Package count — the full `dpkg -l` list is captured once per process
  # (issue #100): this module used to format the 2,000–4,000-row report
  # twice, and check_apps once more with a byte-identical query. Both
  # counts below come from the one shared snapshot.
  local installed_count=0 residual_count=0
  if command -v dpkg >/dev/null 2>&1; then
    perf_capture_dpkg_l || true
    local _dline
    while IFS= read -r _dline; do
      case "$_dline" in
        ii*) installed_count=$((installed_count + 1)) ;;
        rc*) residual_count=$((residual_count + 1)) ;;
      esac
    done <<< "${_PERF_DPKG_L:-}"
    status_info "Installed packages: ${installed_count}"
  fi

  # Held-back packages (all dpkg/apt queries below are timeout-capped with
  # a distinct "timed out" report, #101)
  local held_count _held_rc=0
  tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "apt-mark showhold probe" apt-mark showhold || _held_rc=$?
  if [ "$_held_rc" -ne 124 ]; then
    # In-shell line count (issue #98 convention): a printf|wc pipe would
    # mis-count both empty (1) and newline-stripped (N-1) captures.
    held_count=0
    local _hline
    while IFS= read -r _hline; do
      [ -n "$_hline" ] && held_count=$((held_count + 1))
    done <<< "$_TCAP_OUT"
    if (( held_count > 0 )); then
      status_info "Held-back packages: ${held_count}"
    fi
  fi

  # Broken packages
  local broken_output _br_rc=0
  tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "dpkg audit probe" dpkg --audit || _br_rc=$?
  broken_output="$_TCAP_OUT"
  if [ "$_br_rc" -eq 124 ]; then
    : # tcap already printed the distinct timed-out line — no verdict.
  elif [ -n "$broken_output" ]; then
    status_warn "Broken packages detected"
    add_action "Fix broken packages: sudo dpkg --configure -a && sudo apt --fix-broken install"
  else
    status_ok "No broken packages."
  fi

  # Residual configs (packages removed but config files remain) —
  # counted from the same `dpkg -l` snapshot above.
  if (( residual_count > 5 )); then
    status_info "Packages with residual configs: ${residual_count}"
    add_action "Clean residual configs: sudo apt purge \$(dpkg -l | grep '^rc' | awk '{print \$2}')"
  fi

  # APT cache size
  local cache_size cache_size_raw cache_size_rc=0
  cache_size_raw=$(du_size_kb /var/cache/apt/archives) || cache_size_rc=$?
  if [ "$cache_size_rc" -ne 0 ]; then
    status_info "APT cache size: could not determine"
  else
    cache_size=$(to_int "$cache_size_raw")
    if (( cache_size > 524288 )); then  # > 512 MB
      local cache_hr
      cache_hr=$(kb_to_human "$cache_size")
      status_info "APT cache size: ${cache_hr}"
      add_action "Clean APT cache: sudo apt clean"
    fi
  fi

  # Auto-removable packages
  local autoremove_output autoremove_output_raw _ar_rc=0
  tcap "$MDOCTOR_UPDATE_TIMEOUT_S" "apt-get autoremove simulation" apt-get -s autoremove || _ar_rc=$?
  if [ "$_ar_rc" -ne 124 ]; then
    autoremove_output_raw=$(printf '%s\n' "$_TCAP_OUT" | grep -c '^Remv' || true)
    autoremove_output=$(to_int "$autoremove_output_raw")
    if (( autoremove_output > 0 )); then
      status_info "Auto-removable packages: ${autoremove_output}"
      add_action "Remove unused packages: sudo apt autoremove"
    fi
  fi
}
