#!/usr/bin/env bash
#
# checks/performance.sh
# Performance & memory analysis (read-only, SAFE)
# Category: System
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
check_performance() {
  step "Performance & Memory"

  # Memory pressure level (sampling: lib/perf_probes.sh)
  if is_macos; then
    local pressure_rec pressure _pkey
    pressure_rec=$(perf_probe_mem_pressure 2>/dev/null || true)
    # Record shape is "<platform> <level>" — field split, no fork.
    read -r _pkey pressure _ <<< "$pressure_rec"
    if [ -n "$pressure" ]; then
      case "$pressure" in
        1) status_ok "Memory pressure: normal" ;;
        2) status_warn "Memory pressure: elevated (warn)"
           add_action "Memory pressure is elevated. Close unused applications to free RAM." ;;
        4) status_fail "Memory pressure: critical"
           add_action "Memory pressure is critical. Close applications immediately to prevent slowdowns." ;;
        *) status_info "Memory pressure level: ${pressure}" ;;
      esac
    fi

    # Swap usage (sampling: lib/perf_probes.sh)
    local swap_rec swap_total
    swap_rec=$(perf_probe_swap 2>/dev/null || true)
    swap_total="${swap_rec#macos }"
    if [ -n "$swap_total" ]; then
      status_info "Swap: ${swap_total}"
    fi
  else
    # Linux: memory pressure via MemAvailable ratio (sampling: lib/perf_probes.sh)
    local pressure_rec avail_pct _pkey
    if pressure_rec=$(perf_probe_mem_pressure 2>/dev/null); then
      read -r _pkey avail_pct _ <<< "$pressure_rec"
      if [ -n "$avail_pct" ]; then
        if (( avail_pct < 10 )); then
          status_fail "Memory pressure: critical (${avail_pct}% available)"
          add_action "Memory pressure is critical. Close applications immediately."
        elif (( avail_pct < 25 )); then
          status_warn "Memory pressure: elevated (${avail_pct}% available)"
          add_action "Memory pressure is elevated. Close unused applications to free RAM."
        else
          status_ok "Memory pressure: normal (${avail_pct}% available)"
        fi
      fi
    fi

    # Swap (sampling: lib/perf_probes.sh — "linux <used_kb> <total_kb>")
    local swap_rec swap_total_kb swap_used_kb _skey
    if swap_rec=$(perf_probe_swap 2>/dev/null); then
      read -r _skey swap_used_kb swap_total_kb <<< "$swap_rec"
      if (( ${swap_total_kb:-0} > 0 )); then
        status_info "Swap: $(kb_to_human "$swap_used_kb") used / $(kb_to_human "$swap_total_kb") total"
      fi
    fi
  fi

  # Top 5 CPU-consuming processes (Task 2.5: guarded long-option ps;
  # sampling: lib/perf_probes.sh)
  local top_cpu
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping top-CPU probe: ps not found."
  else
    top_cpu=$(perf_probe_top_cpu_raw 2>/dev/null | head -6 | tail -5 || true)
  fi
  if [ -n "${top_cpu:-}" ]; then
    status_info "Top CPU processes:"
    # read splits each "pid %cpu comm" row in-shell (name keeps the rest
    # of the line) — no echo|awk pipeline per field (issue #98).
    local pid pct name
    while read -r pid pct name; do
      if [ -n "$name" ]; then
        status_info "  PID ${pid}: ${pct}% — ${name}"
      fi
    done <<< "$top_cpu"
  fi

  # Top 5 memory-consuming processes (Task 2.5: guarded long-option ps)
  local top_mem
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping top-memory probe: ps not found."
  else
    if is_macos; then
      top_mem=$(ps -amcwwxo "pid,rss,comm" 2>/dev/null | head -6 | tail -5)
    else
      top_mem=$(ps -eo pid,rss,comm --sort=-rss 2>/dev/null | head -6 | tail -5)
    fi
  fi
  if [ -n "${top_mem:-}" ]; then
    status_info "Top memory processes:"
    local pid rss_kb name mem_hr
    while read -r pid rss_kb name; do
      if [ -n "$name" ] && [ -n "$rss_kb" ] && (( rss_kb > 0 )); then
        mem_hr=$(human_readable_kb "$rss_kb")
        status_info "  PID ${pid}: ${mem_hr} — ${name}"
      fi
    done <<< "$top_mem"
  fi

  # Zombie processes (Task 2.5: guarded ps; sampling: lib/perf_probes.sh —
  # one "<pid> <ppid> <name>" line per zombie; rc 1 when ps is missing)
  local zombie_list zombie_count
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping zombie probe: ps not found."
  else
    zombie_list=$(perf_probe_zombies 2>/dev/null || true)
    if [ -z "$zombie_list" ]; then
      zombie_count=0
    else
      zombie_count=0
      local _zl
      while IFS= read -r _zl; do
        # Non-empty lines only — same set the retired grep -c . counted.
        [ -n "$_zl" ] && zombie_count=$((zombie_count + 1))
      done <<< "$zombie_list"
    fi
    if (( zombie_count > 0 )); then
      status_warn "Zombie processes: ${zombie_count}"
      # List zombie processes with their parent PIDs
      status_info "Zombie process details (PID → Parent PID — Command):"
      local parent_pids=""
      local zpid zppid zname
      while read -r zpid zppid zname; do
        status_info "  PID ${zpid} → Parent ${zppid} — ${zname}"
        if [ -n "$parent_pids" ]; then
          parent_pids="${parent_pids} ${zppid}"
        else
          parent_pids="${zppid}"
        fi
      done <<< "$zombie_list"
      # Deduplicate parent PIDs (newline-split via expansion, one sort).
      local unique_parents
      unique_parents=$(printf '%s\n' "${parent_pids// /$'\n'}" | sort -u)
      unique_parents="${unique_parents//$'\n'/ }"
      if [ -n "$unique_parents" ]; then
        add_action "Found ${zombie_count} zombie process(es). Kill their parent process(es) to clean up: kill -HUP ${unique_parents}"
      fi
    else
      status_ok "No zombie processes."
    fi
  fi

  # Load average assessment (sampling: lib/perf_probes.sh)
  local probe_load cores load1
  if probe_load=$(perf_probe_load 2>/dev/null); then
    read -r load1 cores _ <<< "$probe_load"
    if [ -n "$load1" ] && [ -n "$cores" ]; then
      local load_int
      # trunc(load1*100) via string decimal shift — the retired awk
      # printed %d (truncation), so hundredths come from concatenation,
      # not %.0f rounding (issue #98).
      local _li="${load1%%.*}" _lf=""
      case "$load1" in *.*) _lf="${load1#*.}" ;; esac
      _lf="${_lf%%[!0-9]*}00"
      case "$_li" in ""|*[!0-9]*) _li=0 ;; esac
      load_int=$((10#${_li}${_lf:0:2}))
      local threshold=$((cores * 100))
      if (( load_int > threshold )); then
        status_warn "Load average (${load1}) exceeds CPU core count (${cores})"
        add_action "System load is high. Check running processes with 'top' or 'Activity Monitor'."
      else
        status_ok "Load average (${load1}) within normal range for ${cores} cores."
      fi
    fi
  fi
}
