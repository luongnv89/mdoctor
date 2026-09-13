#!/usr/bin/env bash
#
# checks/battery.sh
# Battery health check (read-only, SAFE)
# Category: Hardware
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
check_battery() {
  step "Battery Health"

  # One capture per report, parsed in-shell (issue #100): this check used
  # to re-invoke the same three slow binaries once per field —
  # system_profiler SPPowerDataType 3× (a sibling comment documents
  # system_profiler as "very slow (~30s)"), ioreg 2× and pmset -g batt 3×.
  local sp_out _spline _sp_rc=0
  # timeout-capped (issue #101): system_profiler is documented as ~30s
  # slow — a wedged run must not masquerade as "no battery".
  sp_out=$(mdoctor_timeout "$MDOCTOR_SYSINFO_TIMEOUT_S" system_profiler SPPowerDataType 2>/dev/null) || _sp_rc=$?
  if [ "$_sp_rc" -eq 124 ]; then
    status_info "Battery probe timed out (timeout ${MDOCTOR_SYSINFO_TIMEOUT_S}s) — skipping battery checks."
    return 0
  fi

  # Detect if this is a desktop Mac (no battery) — count of lines
  # containing "Battery Information" in the single capture above.
  local has_battery=0
  while IFS= read -r _spline; do
    case "$_spline" in
      *"Battery Information"*) has_battery=$((has_battery + 1)) ;;
    esac
  done <<< "$sp_out"

  if (( has_battery == 0 )); then
    status_info "No battery detected (desktop Mac). Skipping battery checks."
    return 0
  fi

  # Battery condition — first "Condition:" line of the same capture;
  # the value after the first ': ' separator, truncated at the next
  # ': ' like the retired awk -F': ' {print $2; exit}.
  local condition=""
  while IFS= read -r _spline; do
    case "$_spline" in
      *Condition:*" "*)
        condition="${_spline#*: }"
        condition="${condition%%: *}"
        break
        ;;
      *Condition:*)
        break   # valueless "Condition:" — awk's $2 was empty here too
        ;;
    esac
  done <<< "$sp_out"
  if [ -n "$condition" ]; then
    if [ "$condition" = "Normal" ]; then
      status_ok "Battery condition: ${condition}"
    else
      status_fail "Battery condition: ${condition}"
      add_action "Battery condition is '${condition}'. Consider having it serviced."
    fi
  fi

  # Cycle count — first "Cycle Count:" line, spaces stripped like the
  # retired gsub(/ /,"",$2).
  local cycle_count=""
  while IFS= read -r _spline; do
    case "$_spline" in
      *"Cycle Count:"*" "*)
        cycle_count="${_spline#*: }"
        cycle_count="${cycle_count%%: *}"
        cycle_count="${cycle_count// /}"
        break
        ;;
      *"Cycle Count:"*)
        break   # valueless — same empty result as the retired awk
        ;;
    esac
  done <<< "$sp_out"
  if [ -n "$cycle_count" ]; then
    if (( cycle_count > 1000 )); then
      status_warn "Battery cycle count: ${cycle_count} (high — above 1000)"
      add_action "Battery has ${cycle_count} cycles. Performance may degrade. Consider replacement."
    else
      status_ok "Battery cycle count: ${cycle_count}"
    fi
  fi

  # Health percentage: AppleRawMaxCapacity / DesignCapacity — one ioreg
  # capture serves both fields; first matching line wins and the value
  # is its trailing digit run (the retired grep -o '[0-9]*$' | head -1).
  local ioreg_out _ioline
  tcap "$MDOCTOR_CMD_TIMEOUT_S" "ioreg battery probe" ioreg -r -c AppleSmartBattery || true
  ioreg_out="$_TCAP_OUT"
  local max_cap="" design_cap=""
  while IFS= read -r _ioline; do
    case "$_ioline" in
      *'"AppleRawMaxCapacity" = '*)
        max_cap="${_ioline##*[!0-9]}"
        break
        ;;
    esac
  done <<< "$ioreg_out"
  while IFS= read -r _ioline; do
    case "$_ioline" in
      *'"DesignCapacity" = '*)
        design_cap="${_ioline##*[!0-9]}"
        break
        ;;
    esac
  done <<< "$ioreg_out"

  if [ -n "$max_cap" ] && [ -n "$design_cap" ] && (( design_cap > 0 )); then
    local health_pct
    health_pct=$(( max_cap * 100 / design_cap ))
    if (( health_pct < 80 )); then
      status_warn "Battery health: ${health_pct}% (below 80%)"
      add_action "Battery health is at ${health_pct}%. Consider replacement for optimal performance."
    else
      status_ok "Battery health: ${health_pct}%"
    fi
  fi

  # Power source, charging status and percent — one `pmset -g batt`
  # capture serves all three fields.
  local pmset_out _pmline
  tcap "$MDOCTOR_CMD_TIMEOUT_S" "pmset battery probe" pmset -g batt || true
  pmset_out="$_TCAP_OUT"

  # Power source: text between the first pair of quotes on the first
  # line (e.g. "Now drawing from 'Battery Power'"). The retired
  # `sed "s/.*'//;s/'.*//"` was greedy — it ate through the last quote
  # and always produced empty — so this restores the intended field.
  local power_source="" _pmfirst
  _pmfirst="${pmset_out%%$'\n'*}"
  case "$_pmfirst" in
    *"'"*"'"*)
      power_source="${_pmfirst#*\'}"
      power_source="${power_source%%\'*}"
      ;;
  esac
  if [ -n "$power_source" ]; then
    status_info "Power source: ${power_source}"
  fi

  # Charging status: first status keyword in output order (leftmost
  # match per line), mirroring the retired
  # grep -o "charging|discharging|charged|finishing charge" | head -1.
  local charging="" _pmw _pmpre _pmbest=-1
  while IFS= read -r _pmline; do
    for _pmw in "finishing charge" discharging charging charged; do
      case "$_pmline" in
        *"$_pmw"*)
          _pmpre="${_pmline%%"$_pmw"*}"
          if (( _pmbest < 0 )) || (( ${#_pmpre} < _pmbest )); then
            _pmbest=${#_pmpre}
            charging="$_pmw"
          fi
          ;;
      esac
    done
    [ -n "$charging" ] && break
  done <<< "$pmset_out"

  # Battery percent: first "<digits>%" in output order — the retired
  # grep -o '[0-9]*%' | head -1 (which could emit a bare "%"; the digit
  # is required here, matching every real pmset line).
  local batt_pct="" _pmpre2
  while IFS= read -r _pmline; do
    case "$_pmline" in
      *[0-9]\%*)
        _pmpre2="${_pmline%%\%*}"
        batt_pct="${_pmpre2##*[!0-9]}%"
        break
        ;;
    esac
  done <<< "$pmset_out"
  if [ -n "$charging" ] && [ -n "$batt_pct" ]; then
    status_info "Battery: ${batt_pct} (${charging})"
  fi
}
