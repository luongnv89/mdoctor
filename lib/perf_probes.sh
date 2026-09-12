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
# Capture-once samplers (issue #100 — F-PERF-011/013/017): the
# perf_capture_* helpers below each capture one slow report — a /proc
# file or an external listing like `vm_stat`, `nproc` or `dpkg -l` — at
# most once per process into a _PERF_* global, and the metric probes
# memoize their live records on top. Consumers parse the shared
# snapshot in-shell instead of re-invoking the binary or re-reading the
# file for every field.
#
# Why setter-globals instead of `$(perf_capture_*)` output: command
# substitution runs the callee in a subshell whose variable writes die
# with it, so a cache filled there can never serve the next call. The
# samplers are therefore direct-call setters — invoke bare
# (`perf_capture_meminfo || true`), then read the _PERF_* variable; any
# later $(perf_probe_*) subshell inherits the populated snapshot, which
# is what lets one read serve every consumer in the run. Drivers that
# know a report will be consumed may prefill it once at the top (see
# check_diagnose_performance); a plain call mid-check works the same.
#
# A separate *_DONE flag distinguishes "captured empty" from "never
# ran" — an empty report must not trigger a re-capture. `cat` reads the
# /proc snapshots deliberately: one fork per process, and the single
# read point stays interceptable by a stub-PATH or function-level cat
# counter in tests.
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

########################################
# CAPTURE-ONCE RAW SAMPLERS (issue #100)
########################################
# Contract per the header comment: direct-call setters, never invoked
# through $(). Each returns 0 when its _PERF_* snapshot is non-empty, 1
# when the source is missing or empty — an empty report still counts as
# captured (the *_DONE flag is what stops re-capture).

# perf_capture_reset — drop every capture + memoized record so a second
# in-process run re-samples (used by check_diagnose_performance, whose
# probes otherwise keep serving the previous run's globals).
perf_capture_reset() {
  _PERF_MEMINFO=""          _PERF_MEMINFO_DONE=""
  _PERF_LOADAVG=""          _PERF_LOADAVG_DONE=""
  _PERF_NPROC=""            _PERF_NPROC_DONE=""
  _PERF_VM_STAT=""          _PERF_VM_STAT_DONE=""
  _PERF_DPKG_L=""           _PERF_DPKG_L_DONE=""
  _PERF_LOAD_L1=""          _PERF_LOAD_CORES=""
  _PERF_LOAD_DONE=""
  _PERF_MEMPRESSURE_LIVE="" _PERF_MEMPRESSURE_DONE=""
  _PERF_SWAP_LIVE=""        _PERF_SWAP_DONE=""
}

# perf_capture_meminfo — read /proc/meminfo once into _PERF_MEMINFO.
perf_capture_meminfo() {
  if ! is_truthy "${_PERF_MEMINFO_DONE:-}"; then
    _PERF_MEMINFO=""
    if [ -r /proc/meminfo ]; then
      _PERF_MEMINFO=$(cat /proc/meminfo 2>/dev/null || true)
    fi
    _PERF_MEMINFO_DONE=true
  fi
  [ -n "$_PERF_MEMINFO" ]
}

# perf_capture_loadavg — read /proc/loadavg once into _PERF_LOADAVG.
perf_capture_loadavg() {
  if ! is_truthy "${_PERF_LOADAVG_DONE:-}"; then
    _PERF_LOADAVG=""
    if [ -r /proc/loadavg ]; then
      _PERF_LOADAVG=$(cat /proc/loadavg 2>/dev/null || true)
    fi
    _PERF_LOADAVG_DONE=true
  fi
  [ -n "$_PERF_LOADAVG" ]
}

# perf_capture_nproc — run nproc once into _PERF_NPROC.
perf_capture_nproc() {
  if ! is_truthy "${_PERF_NPROC_DONE:-}"; then
    _PERF_NPROC=""
    if command -v nproc >/dev/null 2>&1; then
      _PERF_NPROC=$(nproc 2>/dev/null || true)
    fi
    _PERF_NPROC_DONE=true
  fi
  [ -n "$_PERF_NPROC" ]
}

# perf_capture_vm_stat — run vm_stat once into _PERF_VM_STAT (macOS).
perf_capture_vm_stat() {
  if ! is_truthy "${_PERF_VM_STAT_DONE:-}"; then
    _PERF_VM_STAT=""
    if command -v vm_stat >/dev/null 2>&1; then
      _PERF_VM_STAT=$(vm_stat 2>/dev/null || true)
    fi
    _PERF_VM_STAT_DONE=true
  fi
  [ -n "$_PERF_VM_STAT" ]
}

# perf_capture_dpkg_l — run `dpkg -l` once into _PERF_DPKG_L. The full
# package list (2,000–4,000 rows) was formatted three times per check
# run — twice in check_apt, once in check_apps — plus a filtered
# `dpkg -l <pkg>` in check_security that the same snapshot now answers.
perf_capture_dpkg_l() {
  if ! is_truthy "${_PERF_DPKG_L_DONE:-}"; then
    _PERF_DPKG_L=""
    if command -v dpkg >/dev/null 2>&1; then
      _PERF_DPKG_L=$(dpkg -l 2>/dev/null || true)
    fi
    _PERF_DPKG_L_DONE=true
  fi
  [ -n "$_PERF_DPKG_L" ]
}

# perf_probe_load — sample 1-minute load average and logical core count.
# Prints: "<load1> <cores>" (e.g. "1.04 4").
# Returns 1 with no output when either value is indeterminable.
perf_probe_load() {
  local cores load1
  # Memoized live sample (issue #100): the first call per process
  # samples the platform inputs (nproc + /proc/loadavg via the shared
  # captures on Linux, sysctl on macOS); later calls replay the record.
  # DIAG_* fixed inputs are applied after the cached sample so they win
  # on every call — the same rule get_linux_iowait_pct documents.
  if ! is_truthy "${_PERF_LOAD_DONE:-}"; then
    if is_macos; then
      cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
      # vm.loadavg prints "{ 1.23 4.56 7.89 }" — field 2 is load1.
      # In-shell split replaces sysctl|awk (issue #98).
      local _la
      _la=$(sysctl -n vm.loadavg 2>/dev/null || true)
      load1=""
      read -r _ load1 _ <<< "$_la"
    else
      if perf_capture_nproc; then
        cores="$_PERF_NPROC"
      else
        cores=4
      fi
      load1=""
      if perf_capture_loadavg; then
        read -r load1 _ <<< "$_PERF_LOADAVG"
      fi
    fi
    _PERF_LOAD_L1="$load1"
    _PERF_LOAD_CORES="$cores"
    _PERF_LOAD_DONE=true
  else
    load1="$_PERF_LOAD_L1"
    cores="$_PERF_LOAD_CORES"
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
  # Memoized live record (issue #100): the first call per process parses
  # the shared /proc/meminfo snapshot (or the macOS sysctl); later calls
  # replay it. The DIAG_* fixed inputs are re-applied per call on top of
  # the cached record so tests still pin every invocation.
  if ! is_truthy "${_PERF_MEMPRESSURE_DONE:-}"; then
    if is_macos; then
      local pressure
      pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "")
      _PERF_MEMPRESSURE_LIVE="macos ${pressure}"
    else
      # Linux: MemAvailable ratio from the shared /proc/meminfo snapshot
      # (issue #100 — was one open of the file per call).
      _PERF_MEMPRESSURE_LIVE=""
      if perf_capture_meminfo; then
        local mem_total_kb="" mem_avail_kb="" avail_pct
        local _mk _mv _mline
        while IFS= read -r _mline; do
          read -r _mk _mv _ <<< "$_mline"
          case "$_mk" in
            MemTotal:)     mem_total_kb="$_mv" ;;
            MemAvailable:) mem_avail_kb="$_mv" ;;
          esac
        done <<< "$_PERF_MEMINFO"
        if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ] \
          && (( mem_total_kb > 0 )); then
          avail_pct=$(( mem_avail_kb * 100 / mem_total_kb ))
          _PERF_MEMPRESSURE_LIVE="linux ${avail_pct}"
        fi
      fi
    fi
    _PERF_MEMPRESSURE_DONE=true
  fi
  if [ -z "$_PERF_MEMPRESSURE_LIVE" ]; then
    return 1
  fi

  # Fixed inputs for tests (see header comment).
  local rec="$_PERF_MEMPRESSURE_LIVE"
  case "$rec" in
    macos\ *)
      if [ -n "${DIAG_MEM_PRESSURE_LEVEL:-}" ]; then
        rec="macos ${DIAG_MEM_PRESSURE_LEVEL}"
      fi
      ;;
    linux\ *)
      if [ -n "${DIAG_MEM_AVAIL_PCT:-}" ]; then
        rec="linux ${DIAG_MEM_AVAIL_PCT}"
      fi
      ;;
  esac
  echo "$rec"
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
  # Memoized live record (issue #100): the first call per process parses
  # the shared /proc/meminfo snapshot (or the macOS sysctl); later calls
  # replay the same "<platform> ..." record — the swap value is derived
  # once, not once per consumer.
  if ! is_truthy "${_PERF_SWAP_DONE:-}"; then
    if is_macos; then
      local raw
      raw=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
      _PERF_SWAP_LIVE="macos ${raw}"
    else
      _PERF_SWAP_LIVE=""
      if perf_capture_meminfo; then
        local swap_total_kb="" swap_free_kb="" swap_used_kb
        local _mk _mv _mline
        while IFS= read -r _mline; do
          read -r _mk _mv _ <<< "$_mline"
          case "$_mk" in
            SwapTotal:) swap_total_kb="$_mv" ;;
            SwapFree:)  swap_free_kb="$_mv" ;;
          esac
        done <<< "$_PERF_MEMINFO"
        if [ -n "$swap_total_kb" ] && [ -n "$swap_free_kb" ]; then
          swap_used_kb=$((swap_total_kb - swap_free_kb))
          _PERF_SWAP_LIVE="linux ${swap_used_kb} ${swap_total_kb}"
        fi
      fi
    fi
    _PERF_SWAP_DONE=true
  fi
  if [ -z "$_PERF_SWAP_LIVE" ]; then
    return 1
  fi
  echo "$_PERF_SWAP_LIVE"
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
  # In-shell row filter replaces the awk '$3 ~ /^Z/' stage (issue #98);
  # the record shape is identical ("<pid> <ppid> <name>").
  local _zp _zpp _zs _zc
  ps -eo pid,ppid,stat,comm 2>/dev/null | while read -r _zp _zpp _zs _zc _; do
    case "$_zs" in
      Z*) printf '%s %s %s\n' "$_zp" "$_zpp" "$_zc" ;;
    esac
  done || true
}
