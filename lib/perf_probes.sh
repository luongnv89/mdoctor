#!/usr/bin/env bash
#
# lib/perf_probes.sh
# Shared performance samplers (issues #87/#88 — F-DEAD-015).
# checks/performance.sh and checks/diagnose_performance.sh previously
# sampled the same five platform metrics with their own inline branches
# (load average, top-CPU table, memory pressure, swap usage, zombie scan);
# each sampler below is the single definition site for one metric,
# following the lib/disk.sh precedent (du_size_kb, disk_used_pct_root).
#
# Sink contract: probes are sink-agnostic. They never call status_*,
# add_action, or add_diagnosis_action — they print one machine-readable
# record to stdout and let the caller (the sink) capture it via command
# substitution and report with its own severity vocabulary. Passing a
# different sink therefore means capturing probe stdout in a different
# caller; no probe hardcodes its consumer.
#
# Platform branching gates on lib/platform.sh predicates (is_macos /
# is_linux) only — never on uname output directly.
#
# Test overrides (inherited from checks/diagnose_performance.sh): the
# native-unit probes honor a DIAG_* environment override so tests feed
# fixed inputs deterministically:
#   DIAG_LOADAVG / DIAG_CORES .... load average and core count
#   DIAG_MEM_AVAIL_PCT ........... memory available percent (pressure, Linux)
#   DIAG_MEM_PRESSURE_LEVEL ...... memory pressure level (macOS sysctl value)
# Swap thresholds key on a caller-derived percent rather than a native
# unit, so DIAG_SWAP_PCT stays in the callers (applied after the percent
# derivation): synthesizing kb inside the probe would change the live kb
# values the callers display. The swap probe itself is a pure sampler.
#

# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate.
_MDOCTOR_TRUTHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
# shellcheck source=/dev/null
source "${_MDOCTOR_TRUTHY_DIR}/constants.sh"
unset _MDOCTOR_TRUTHY_DIR

# Guard against double-sourcing.
if is_truthy "${_MDOCTOR_PERF_PROBES_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PERF_PROBES_LOADED=true

# perf_probe_load — sample 1-minute load average and logical core count.
# Prints: "<load1> <cores>" (e.g. "1.04 4").
# Returns 1 with no output when either value is indeterminable.
perf_probe_load() {
  local cores load1
  if is_macos; then
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  else
    cores=$(nproc 2>/dev/null || echo 4)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "")
  fi

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_LOADAVG:-}" ]; then
    load1="$DIAG_LOADAVG"
  fi
  if [ -n "${DIAG_CORES:-}" ]; then
    cores="$DIAG_CORES"
  fi

  if [ -z "$load1" ] || [ -z "$cores" ]; then
    return 1
  fi
  echo "${load1} ${cores}"
}

# perf_probe_top_cpu_raw — sample the raw top-CPU process table, header
# row included. Callers slice off the header with head/tail for their own
# row count (check takes 5, diagnose takes 10), preserving each caller's
# exact historical line selection including short-table edge cases.
# macOS columns : pid %cpu comm (resorted by -r flag).
# Linux columns : pid %cpu comm (sorted by --sort=-%cpu).
# Returns 1 with no output when ps is missing or yields nothing.
perf_probe_top_cpu_raw() {
  if ! command -v ps >/dev/null 2>&1; then
    return 1
  fi
  local raw
  if is_macos; then
    raw=$(ps -arcwwxo "pid,%cpu,comm" 2>/dev/null || true)
  else
    raw=$(ps -eo pid,%cpu,comm --sort=-%cpu 2>/dev/null || true)
  fi
  if [ -z "$raw" ]; then
    return 1
  fi
  echo "$raw"
}

# perf_probe_mem_pressure — sample memory pressure in platform-native units.
# Prints one record:
#   "macos <level>" ..... kern.memorystatus_vm_pressure_level (may be empty)
#   "linux <avail_pct>" . MemAvailable percent of MemTotal (integer)
# Returns 1 with no output when the pressure is indeterminable (Linux only:
# unreadable /proc/meminfo, or missing/non-positive MemTotal).
perf_probe_mem_pressure() {
  if is_macos; then
    local pressure
    pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "")

    # Fixed inputs for tests (see header comment).
    if [ -n "${DIAG_MEM_PRESSURE_LEVEL:-}" ]; then
      pressure="$DIAG_MEM_PRESSURE_LEVEL"
    fi

    echo "macos ${pressure}"
    return 0
  fi

  # Linux: MemAvailable ratio.
  if [ ! -r /proc/meminfo ]; then
    return 1
  fi
  local mem_total_kb mem_avail_kb avail_pct
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  if [ -z "$mem_total_kb" ] || [ -z "$mem_avail_kb" ]; then
    return 1
  fi
  if ! (( mem_total_kb > 0 )); then
    return 1
  fi
  avail_pct=$(( mem_avail_kb * 100 / mem_total_kb ))

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_MEM_AVAIL_PCT:-}" ]; then
    avail_pct="$DIAG_MEM_AVAIL_PCT"
  fi

  echo "linux ${avail_pct}"
}

# perf_probe_swap — sample swap usage in platform-native units.
# Prints one record:
#   "macos <raw>" .............. `sysctl -n vm.swapusage` (may be empty)
#   "linux <used_kb> <total_kb>"  SwapTotal/SwapFree from /proc/meminfo
# macOS always succeeds (callers treat an empty raw as "unavailable",
# mirroring perf_probe_mem_pressure); Linux returns 1 with no output when
# /proc/meminfo is unreadable or carries no swap fields. Callers derive
# the threshold percent from the record and apply DIAG_SWAP_PCT there
# (see header comment).
perf_probe_swap() {
  if is_macos; then
    local raw
    raw=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
    echo "macos ${raw}"
    return 0
  fi

  if [ ! -r /proc/meminfo ]; then
    return 1
  fi
  local swap_total_kb swap_free_kb swap_used_kb
  swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  swap_free_kb=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
  if [ -z "$swap_total_kb" ] || [ -z "$swap_free_kb" ]; then
    return 1
  fi
  swap_used_kb=$((${swap_total_kb:-0} - ${swap_free_kb:-0}))
  echo "linux ${swap_used_kb} ${swap_total_kb}"
}

# perf_probe_zombies — sample zombie processes.
# Prints one "<pid> <ppid> <name>" line per zombie (the same
# `ps -eo pid,ppid,stat,comm` + `$3 ~ /^Z/` shape both callers previously
# inlined, so counts and details agree by construction). Empty output
# with rc 0 when there are no zombies; rc 1 with no output when ps is
# missing. Callers derive the count from the line count.
perf_probe_zombies() {
  if ! command -v ps >/dev/null 2>&1; then
    return 1
  fi
  ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/ {print $1, $2, $4}' || true
}
