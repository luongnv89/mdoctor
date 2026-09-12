#!/usr/bin/env bash
#
# checks/diagnose_performance.sh
# Active performance diagnosis with bottleneck detection.
# Category: System | Risk: HIGH (active checks only, no modifications)
#
# Sources: lib/platform.sh, lib/common.sh
#


# Diagnosis recommendations are printed by severity in the summary.
# Keep the global ACTIONS list populated for compatibility with existing
# check-module conventions while tracking explicit priority locally.
#
# Injectable metric sources (issue #74): every threshold probe below
# honors a DIAG_* environment override so tests can feed fixed inputs and
# assert both the healthy and the unhealthy branch deterministically,
# independent of the host's live metrics. Each override is numeric and
# applies after the live probe, just before the threshold comparison:
#   DIAG_LOADAVG / DIAG_CORES .... load average and core count
#   DIAG_MEM_PCT ................. memory usage percent
#   DIAG_MEM_AVAIL_PCT ........... memory available percent (pressure, Linux)
#   DIAG_MEM_PRESSURE_LEVEL ...... memory pressure level (macOS sysctl value)
#   DIAG_DISK_PCT ................ root disk usage percent
#   DIAG_SWAP_PCT ................ swap usage percent
#   DIAG_LINUX_IOWAIT_PCT ........ sampled CPU iowait percent (pre-existing)
#   DIAG_CPU_USER_PCT / DIAG_CPU_SYS_PCT .. user/kernel CPU time split
# (Issue #87: the load, top-CPU and memory-pressure samplers live in
# lib/perf_probes.sh; their DIAG_* overrides are applied inside the
# shared probe so both callers stay deterministic under test.)

# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
add_diagnosis_action() {
  local severity="${1-}"
  local msg="${2-}"
  [ -z "$msg" ] && return 0
  ACTIONS+=("$msg")
  case "$severity" in
    critical) ACTIONS_CRITICAL+=("$msg") ;;
    *) ACTIONS_WARNING+=("$msg") ;;
  esac
}

get_linux_iowait_pct() {
  # An explicit DIAG_LINUX_IOWAIT_PCT is a fixed test input and always
  # wins. Live samples are cached in _DIAG_IOWAIT_CACHED (a separate
  # variable) so resetting the cache never wipes a test override.
  if [ -n "${DIAG_LINUX_IOWAIT_PCT:-}" ]; then
    echo "$DIAG_LINUX_IOWAIT_PCT"
    return 0
  fi

  if [ -n "${_DIAG_IOWAIT_CACHED:-}" ]; then
    echo "$_DIAG_IOWAIT_CACHED"
    return 0
  fi

  if ! is_linux || [ ! -r /proc/stat ]; then
    echo 0
    return 0
  fi

  local user1 nice1 system1 idle1 iowait1 irq1 soft_irq1 steal1
  local user2 nice2 system2 idle2 iowait2 irq2 soft_irq2 steal2
  local total1 total2 total_delta iowait_delta

  read -r _ user1 nice1 system1 idle1 iowait1 irq1 soft_irq1 steal1 _ _ _ < <(head -1 /proc/stat)
  sleep 0.2
  read -r _ user2 nice2 system2 idle2 iowait2 irq2 soft_irq2 steal2 _ _ _ < <(head -1 /proc/stat)

  total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + soft_irq1 + steal1))
  total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + soft_irq2 + steal2))
  total_delta=$((total2 - total1))
  iowait_delta=$((iowait2 - iowait1))

  if (( total_delta > 0 && iowait_delta >= 0 )); then
    _DIAG_IOWAIT_CACHED=$((iowait_delta * 100 / total_delta))
  else
    _DIAG_IOWAIT_CACHED=0
  fi

  echo "$_DIAG_IOWAIT_CACHED"
}

########################################
# CHECK: Load Average vs Core Count
########################################

check_load_average() {
  local cores load1 load_int threshold
  local ratio_pct
  local probe_load

  # Sampling: lib/perf_probes.sh (DIAG_LOADAVG / DIAG_CORES overrides
  # are applied inside the probe).
  if ! probe_load=$(perf_probe_load 2>/dev/null); then
    status_info "Load average: unable to determine"
    return 0
  fi
  read -r load1 cores _ <<< "$probe_load"

  if [ -z "$load1" ] || [ -z "$cores" ]; then
    status_info "Load average: unable to determine"
    return 0
  fi

  # Convert to integers (load1 * 100) via string decimal shift — the
  # retired awk printed %d (truncation), so hundredths come from
  # concatenation, not %.0f rounding (issue #98).
  local _li="${load1%%.*}" _lf=""
  case "$load1" in *.*) _lf="${load1#*.}" ;; esac
  _lf="${_lf%%[!0-9]*}00"
  case "$_li" in ""|*[!0-9]*) _li=0 ;; esac
  load_int=$((10#${_li}${_lf:0:2}))
  threshold=$((cores * 100))
  # ratio = (l/c)*100 = load_int/cores, rounded half-even like %.0f.
  if (( cores > 0 )); then
    ratio_pct=$((load_int / cores))
    local _rem=$((load_int % cores))
    if (( _rem * 2 > cores )) || { (( _rem * 2 == cores )) && (( ratio_pct % 2 == 1 )); }; then
      ratio_pct=$((ratio_pct + 1))
    fi
  else
    ratio_pct=0
  fi

  if (( load_int > threshold * MDOCTOR_DIAG_LOAD_OVER_MULT )); then
    status_fail "Load average (${load1}) is >2x core count (${cores}) [${ratio_pct}% ratio]"
    add_diagnosis_action "critical" "System is severely overloaded. Run 'top' or 'htop' to identify runaway processes."
  elif (( load_int > threshold )); then
    status_warn "Load average (${load1}) exceeds core count (${cores}) [${ratio_pct}% ratio]"
    add_diagnosis_action "warning" "System load is high. Check running processes with 'top' or 'Activity Monitor'."
  else
    status_ok "Load average (${load1}) within normal range for ${cores} cores [${ratio_pct}%]"
  fi
}

########################################
# CHECK: Top CPU Consumers
########################################

check_top_cpu_consumers() {
  local top_cpu pid pct name
  local high_count=0

  # Task 2.5: guarded long-option ps; absent ps reports a skip.
  # Sampling: lib/perf_probes.sh (row slicing keeps this caller's top-10).
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping top-CPU probe: ps not found."
    return 0
  fi

  top_cpu=$(perf_probe_top_cpu_raw 2>/dev/null | head -11 | tail -10 || true)

  if [ -z "$top_cpu" ]; then
    status_info "Top CPU processes: unable to retrieve"
    return 0
  fi

  status_info "Top 10 CPU-consuming processes:"
  # read splits each "pid %cpu comm" row in-shell — name keeps the rest
  # of the line, no echo|awk pipeline per field (issue #98).
  while read -r pid pct name; do
    [ -z "$name" ] && continue

    if [ -n "$pct" ]; then
      local pct_int
      pct_int="${pct%%.*}"   # %d truncation: "45.0"→"45"
      if (( pct_int > MDOCTOR_DIAG_CPU_HIGH )); then
        status_fail "PID ${pid}: ${pct}% — ${name} (critical consumer)"
        add_diagnosis_action "critical" "Process '${name}' (PID ${pid}) is consuming ${pct}% CPU. Investigate or terminate with 'kill ${pid}'."
        high_count=$((high_count + 1))
      elif (( pct_int > MDOCTOR_DIAG_CPU_MED )); then
        status_warn "PID ${pid}: ${pct}% — ${name} (high consumer)"
        add_diagnosis_action "warning" "Process '${name}' (PID ${pid}) is consuming ${pct}% CPU. Consider monitoring or limiting its resource usage."
      fi
    fi
  done <<< "$top_cpu"

  if (( high_count == 0 )); then
    status_ok "No process exceeds 80% CPU usage."
  fi
}

########################################
# CHECK: Memory Usage
########################################

check_memory_usage() {
  local total_kb used_kb avail_kb pct

  if is_macos; then
    # macOS: use sysctl for physical memory stats
    local page_size active_pages wired_pages total_bytes
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo "$MDOCTOR_PAGE_SIZE_FALLBACK")
    # One vm_stat capture, field-split in-shell (issue #98).
    local vm_out vline _v1 _v2 _v3
    vm_out=$(vm_stat 2>/dev/null || true)
    active_pages=""
    wired_pages=""
    while IFS= read -r vline; do
      case "$vline" in
        "Pages active:"*)
          read -r _v1 _v2 active_pages _ <<< "$vline"
          active_pages="${active_pages//[^0-9]/}"
          ;;
        "Pages wired down:"*)
          read -r _v1 _v2 _v3 wired_pages <<< "$vline"
          wired_pages="${wired_pages//[^0-9]/}"
          ;;
      esac
    done <<< "$vm_out"

    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
    local active_kb wired_kb
    active_kb=$(( ${active_pages:-0} * page_size / MDOCTOR_BYTES_PER_KB ))
    wired_kb=$(( ${wired_pages:-0} * page_size / MDOCTOR_BYTES_PER_KB ))
    local used_kb=$((active_kb + wired_kb))
    total_kb=$(( ${total_bytes:-0} / MDOCTOR_BYTES_PER_KB ))

    if (( total_kb > 0 )); then
      pct=$((used_kb * 100 / total_kb))
    else
      pct=0
    fi
  else
    # Linux: use /proc/meminfo — one in-shell pass for both fields
    # (issue #98; previously two awk opens of the same file).
    total_kb=""
    avail_kb=""
    local _mk _mv _mline
    while IFS= read -r _mline; do
      read -r _mk _mv _ <<< "$_mline"
      case "$_mk" in
        MemTotal:)     total_kb="$_mv" ;;
        MemAvailable:) avail_kb="$_mv" ;;
      esac
    done 2>/dev/null < /proc/meminfo
    used_kb=$(( ${total_kb:-0} - ${avail_kb:-0} ))

    if (( ${total_kb:-0} > 0 )); then
      pct=$((used_kb * 100 / total_kb))
    else
      pct=0
    fi
  fi

  # Format sizes via the single shared ladder (Task 8.2).
  local total_hr used_hr
  total_hr=$(human_readable_kb "$total_kb")
  used_hr=$(human_readable_kb "$used_kb")

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_MEM_PCT:-}" ]; then
    pct="$DIAG_MEM_PCT"
  fi

  if (( pct > MDOCTOR_DIAG_MEM_CRIT )); then
    status_fail "Memory: ${pct}% used (${used_hr}/${total_hr}) — OOM risk!"
    add_diagnosis_action "critical" "Memory usage is critical. Close applications immediately to avoid out-of-memory crashes."
  elif (( pct > MDOCTOR_DIAG_MEM_WARN )); then
    status_warn "Memory: ${pct}% used (${used_hr}/${total_hr}) — high usage"
    add_diagnosis_action "warning" "Memory usage is high. Review memory consumers with 'top' or 'Activity Monitor'."
  else
    status_ok "Memory: ${pct}% used (${used_hr}/${total_hr})"
  fi
}

########################################
# CHECK: Memory Pressure
########################################

check_memory_pressure() {
  # Sampling: lib/perf_probes.sh (DIAG_MEM_PRESSURE_LEVEL /
  # DIAG_MEM_AVAIL_PCT overrides are applied inside the probe).
  if is_macos; then
    local pressure_rec pressure _pkey
    pressure_rec=$(perf_probe_mem_pressure 2>/dev/null || true)
    read -r _pkey pressure _ <<< "$pressure_rec"

    case "$pressure" in
      1) status_ok "Memory pressure: normal" ;;
      2) status_warn "Memory pressure: elevated"
         add_diagnosis_action "warning" "Memory pressure is elevated. Close unused applications to free RAM." ;;
      4) status_fail "Memory pressure: critical"
         add_diagnosis_action "critical" "Memory pressure is critical. Close applications immediately to prevent slowdowns." ;;
      *) status_info "Memory pressure level: ${pressure:-unknown}" ;;
    esac
  else
    # Linux: MemAvailable ratio (sampling: lib/perf_probes.sh)
    if [ -r /proc/meminfo ]; then
      local pressure_rec avail_pct _pkey
      if pressure_rec=$(perf_probe_mem_pressure 2>/dev/null); then
        read -r _pkey avail_pct _ <<< "$pressure_rec"
        if (( avail_pct < MDOCTOR_DIAG_MEM_FREE_CRIT )); then
          status_fail "Memory pressure: critical (${avail_pct}% available)"
          add_diagnosis_action "critical" "Memory pressure is critical. Close applications immediately."
        elif (( avail_pct < MDOCTOR_DIAG_MEM_FREE_WARN )); then
          status_warn "Memory pressure: elevated (${avail_pct}% available)"
          add_diagnosis_action "warning" "Memory pressure is elevated. Close unused applications to free RAM."
        else
          status_ok "Memory pressure: normal (${avail_pct}% available)"
        fi
      else
        status_info "Memory pressure: unable to determine (MemAvailable unavailable)"
      fi
    fi
  fi
}

########################################
# CHECK: Swap Usage
########################################

check_swap_usage() {
  local pct swap_hr

  if is_macos; then
    # Sampling: lib/perf_probes.sh ("macos <raw>").
    local swap_rec swap_total_raw
    swap_rec=$(perf_probe_swap 2>/dev/null || true)
    swap_total_raw="${swap_rec#macos }"
    if [ -n "$swap_total_raw" ]; then
      status_info "Swap: ${swap_total_raw}"

      # Try to get actual usage from vm_stat — one capture, in-shell split.
      local swap_in="" swap_out="" vm_out vline _v1 _v2 _v3
      vm_out=$(vm_stat 2>/dev/null || true)
      while IFS= read -r vline; do
        case "$vline" in
          "Pages swapped in"*)
            read -r _v1 _v2 _v3 swap_in <<< "$vline"
            swap_in="${swap_in//[^0-9]/}"
            ;;
          "Pages swapped out"*)
            read -r _v1 _v2 _v3 swap_out <<< "$vline"
            swap_out="${swap_out//[^0-9]/}"
            ;;
        esac
      done <<< "$vm_out"
      status_info "Swap activity: $((${swap_in:-0} + ${swap_out:-0})) pages total"
    else
      status_info "Swap: unavailable"
    fi
  else
    # Sampling: lib/perf_probes.sh ("linux <used_kb> <total_kb>").
    local swap_rec swap_used swap_total _skey
    swap_rec=$(perf_probe_swap 2>/dev/null || true)
    read -r _skey swap_used swap_total <<< "$swap_rec"
    swap_total="${swap_total:-0}"
    swap_used="${swap_used:-0}"

    if (( swap_total > 0 )); then
      pct=$((swap_used * 100 / swap_total))
      swap_hr=$(kb_to_human "$swap_used")
    else
      pct=0
      swap_hr="0 KB"
    fi

    # Fixed inputs for tests (see header comment).
    if [ -n "${DIAG_SWAP_PCT:-}" ]; then
      pct="$DIAG_SWAP_PCT"
    fi

    if (( pct > MDOCTOR_DIAG_SWAP_HIGH )); then
      status_fail "Swap: ${pct}% used (${swap_hr}/${swap_total} KB) — critical"
      add_diagnosis_action "critical" "Swap usage is critical. System is relying heavily on swap. Consider adding more RAM or reducing workload."
    elif (( pct > MDOCTOR_DIAG_SWAP_MED )); then
      status_warn "Swap: ${pct}% used (${swap_hr}/${swap_total} KB)"
      add_diagnosis_action "warning" "Swap usage is high. Consider closing memory-intensive applications."
    else
      status_ok "Swap: ${pct}% used (${swap_hr}/${swap_total} KB)"
    fi
  fi
}

########################################
# CHECK: Disk I/O — iowait
########################################

check_disk_iowait() {
  local iowait_pct

  if is_linux && [ -f /proc/stat ]; then
    # Sample /proc/stat over a short interval; cumulative counters since boot
    # can hide current disk I/O spikes on long-running systems.
    iowait_pct=$(get_linux_iowait_pct)
  elif is_macos; then
    # macOS does not expose Linux-style CPU iowait. Avoid deriving disk
    # contention from vm_stat memory counters because wired/active pages are
    # unrelated to disk wait and produce misleading remediation advice.
    status_info "Disk I/O wait: unavailable on macOS (use Activity Monitor or 'iostat -w 1' for live disk activity)"
    return 0
  else
    status_info "Disk I/O: unable to determine iowait"
    return 0
  fi

  if (( iowait_pct > MDOCTOR_DIAG_IOWAIT_HIGH )); then
    status_fail "Disk I/O wait: ${iowait_pct}% — severe bottleneck"
    add_diagnosis_action "critical" "Disk I/O is a critical bottleneck. Check for heavy disk operations with 'iotop' or 'sudo iotop -o'."
  elif (( iowait_pct > MDOCTOR_DIAG_IOWAIT_MED )); then
    status_warn "Disk I/O wait: ${iowait_pct}% — elevated"
    add_diagnosis_action "warning" "Disk I/O wait is elevated. Identify slow disk operations and consider SSD upgrade if on HDD."
  else
    status_ok "Disk I/O wait: ${iowait_pct}% — normal"
  fi
}

########################################
# CHECK: Disk Usage Hotspots
########################################

check_disk_hotspots() {
  local root_disk_pct

  # lib/disk.sh resolves the platform-correct root path once per process
  # (APFS Data volume on macOS, / elsewhere — same fallback this block
  # used to spell out) and returns MDOCTOR_SIZE_ERR_* on failure, which
  # leaves root_disk_pct empty like the old awk-on-empty-df path.
  root_disk_pct=$(disk_used_pct_root 2>/dev/null || true)

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_DISK_PCT:-}" ]; then
    root_disk_pct="$DIAG_DISK_PCT"
  fi

  if [ -n "$root_disk_pct" ]; then
    if (( root_disk_pct > MDOCTOR_DIAG_DISK_CRIT )); then
      status_fail "Root disk usage: ${root_disk_pct}% — critical!"
      add_diagnosis_action "critical" "Root disk is nearly full. Remove unnecessary files immediately with 'mdoctor clean'."
    elif (( root_disk_pct > MDOCTOR_DIAG_DISK_WARN )); then
      status_warn "Root disk usage: ${root_disk_pct}% — high"
      add_diagnosis_action "warning" "Root disk is nearly full. Consider cleanup with 'mdoctor clean' to reclaim space."
    else
      status_ok "Root disk usage: ${root_disk_pct}%"
    fi
  fi

  # Check for large temp/cache directories (fast: only scan known small dirs)
  # Skip deep home directory scans — they are too slow for a diagnostic check
  local large_dirs=""
  local dir_size dir_hr dir_size_rc
  local -a fast_dirs=("/tmp" /var/log /var/tmp)
  for dir in "${fast_dirs[@]}"; do
    [ ! -d "$dir" ] && continue
    dir_size_rc=0
    dir_size=$(du_size_kb "$dir") || dir_size_rc=$?
    if [ "$dir_size_rc" -ne 0 ]; then
      status_info "Size of ${dir}: could not determine."
    elif (( dir_size > MDOCTOR_DIAG_DIR_WARN_KB )); then
      dir_hr=$(kb_to_human "$dir_size")
      large_dirs="${large_dirs}  ${dir}: ${dir_hr}\n"
    fi
  done

  if [ -n "$large_dirs" ]; then
    status_info "Large system directories (>1 GB):"
    printf "%b" "$large_dirs"
  fi
}

########################################
# CHECK: Zombie Processes
########################################

check_zombie_processes() {
  # Task 2.5: guarded ps; absent ps reports a skip.
  # Sampling: lib/perf_probes.sh (one "<pid> <ppid> <name>" line per
  # zombie; the count derives from the probe lines, so count and details
  # agree by construction).
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping zombie probe: ps not found."
    return 0
  fi

  local zombie_list zombie_count parent_pids unique_parents
  zombie_list=$(perf_probe_zombies 2>/dev/null || true)

  if [ -z "$zombie_list" ]; then
    zombie_count=0
  else
    zombie_count=$(printf '%s\n' "$zombie_list" | grep -c . || true)
  fi

  if (( zombie_count > 0 )); then
    status_warn "Zombie processes: ${zombie_count}"

    parent_pids=""
    local zpid zppid zname
    while read -r zpid zppid zname; do
      status_info "  PID ${zpid} → Parent ${zppid} — ${zname}"
      if [ -n "$parent_pids" ]; then
        parent_pids="${parent_pids} ${zppid}"
      else
        parent_pids="${zppid}"
      fi
    done <<< "$zombie_list"

    # Dedupe parent PIDs (newline-split via expansion, one sort).
    unique_parents=$(printf '%s\n' "${parent_pids// /$'\n'}" | sort -un)
    unique_parents="${unique_parents//$'\n'/ }"
    if [ -n "$unique_parents" ]; then
      add_diagnosis_action "warning" "Kill zombie parent processes: kill -HUP ${unique_parents}"
    fi
  else
    status_ok "No zombie processes."
  fi
}

########################################
# CHECK: File Descriptor Limits
########################################

check_fd_limits() {
  local fd_limit fd_open_pct

  # Estimate open file descriptors (platform-specific fast methods)
  local open_fds=0
  if is_macos; then
    # macOS: use sysctl for system-wide file descriptor count (no lsof scan)
    local open_files
    open_files=$(sysctl -n kern.num_files 2>/dev/null || true)
    open_files="${open_files//[[:space:]]/}"
    fd_limit=$(sysctl -n kern.maxfiles 2>/dev/null || true)
    fd_limit="${fd_limit%%[[:space:]]*}"   # first field, like awk '{print $1}'
    if [ -n "$open_files" ] && [ -n "$fd_limit" ] && (( fd_limit > 0 )) 2>/dev/null; then
      open_files=$((open_files + 0))
      fd_limit=$((fd_limit + 0))
      open_fds=$((open_files))
    fi
  elif is_linux && [ -f /proc/sys/fs/file-nr ]; then
    # Linux: read from /proc/sys/fs/file-nr (system-wide, fast).
    # Format: allocated unused max. The max field is the system-wide limit;
    # do not compare system-wide allocated FDs against per-process ulimit -n.
    local file_nr
    # $(< file) emits its own redirection error when the open fails, so
    # keep the -f probe (already above) and an explicit readable guard.
    file_nr=""
    if [ -r /proc/sys/fs/file-nr ]; then
      file_nr=$(< /proc/sys/fs/file-nr)
    fi
    # Format "allocated unused max" — in-shell split, numeric coercion.
    read -r open_fds _fd_unused fd_limit <<< "$file_nr"
    case "$open_fds" in ''|*[!0-9]*) open_fds=0 ;; esac
    case "$fd_limit" in ''|*[!0-9]*) fd_limit=0 ;; esac
    if (( ${fd_limit:-0} <= 0 )) && [ -r /proc/sys/fs/file-max ]; then
      fd_limit=$(< /proc/sys/fs/file-max)
      fd_limit="${fd_limit//[[:space:]]/}"
    fi
  fi

  fd_limit=${fd_limit:-0}
  if (( fd_limit > 0 )); then
    fd_open_pct=$((open_fds * 100 / fd_limit))
  else
    fd_open_pct=0
  fi

  if (( fd_open_pct > MDOCTOR_DIAG_FD_HIGH )); then
    status_fail "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
    add_diagnosis_action "critical" "File descriptor limit is nearly reached. Increase with 'ulimit -n <new_limit>' or adjust /etc/security/limits.conf."
  elif (( fd_open_pct > MDOCTOR_DIAG_FD_MED )); then
    status_warn "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
    add_diagnosis_action "warning" "File descriptor usage is moderate. Monitor for potential limits on busy servers."
  else
    status_ok "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
  fi
}

########################################
# CHECK: Open Network Connections
########################################

check_open_connections() {
  local conn_count
  local conn_detail=""

  # One socket-table snapshot per platform, counted in-shell (issue #98:
  # the table used to be sampled once per counter).
  if is_macos; then
    local conn_snap
    conn_snap=$(netstat -an 2>/dev/null || true)
    conn_count=0
    conn_detail=0
    local _cl
    while IFS= read -r _cl; do
      case "$_cl" in
        *ESTABLISHED*) conn_count=$((conn_count + 1)) ;;
        *LISTEN*)      conn_detail=$((conn_detail + 1)) ;;
      esac
    done <<< "$conn_snap"
  else
    # Task 2.5: guarded ss; absent ss reports a skip and counts as zero.
    if ! command -v ss >/dev/null 2>&1; then
      status_info "Skipping connection-count probe: ss not found."
      conn_count=0
      conn_detail=0
    else
      local conn_snap
      conn_snap=$(ss -tun 2>/dev/null || true)
      conn_count=0
      conn_detail=0
      local _cl
      while IFS= read -r _cl; do
        case "$_cl" in
          *ESTAB*)  conn_count=$((conn_count + 1)) ;;
          *LISTEN*) conn_detail=$((conn_detail + 1)) ;;
        esac
      done <<< "$conn_snap"
    fi
  fi

  if (( conn_count > MDOCTOR_DIAG_CONN_HIGH )); then
    status_fail "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail}) — critical"
    add_diagnosis_action "critical" "Unusually high number of open connections. Investigate with 'netstat -ant' or 'ss -tunap'."
  elif (( conn_count > MDOCTOR_DIAG_CONN_MED )); then
    status_warn "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail})"
    add_diagnosis_action "warning" "High number of open connections. Monitor for potential connection leaks."
  else
    status_ok "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail})"
  fi
}

########################################
# CHECK: Swap Thrashing Detection
########################################

check_swap_thrashing() {
  local swap_pct=0 iowait_pct=0

  # Sampling: lib/perf_probes.sh (swap record; the DIAG_SWAP_PCT fixed
  # input stays below — it keys on the derived percent, see probe header).
  if is_macos; then
    local swap_rec swap_total_raw swap_total_mb="" swap_used_mb=""
    swap_rec=$(perf_probe_swap 2>/dev/null || true)
    swap_total_raw="${swap_rec#macos }"
    if [ -n "$swap_total_raw" ]; then
      # Format varies by macOS version: "0.00M" or "0.00Mb" — BASH_REMATCH
      # extracts the numbers in-shell (issue #98).
      local _swap_re='total = ([0-9.]+)[Mm]'
      if [[ "$swap_total_raw" =~ $_swap_re ]]; then
        swap_total_mb="${BASH_REMATCH[1]}"
      fi
      _swap_re='used = ([0-9.]+)[Mm]'
      if [[ "$swap_total_raw" =~ $_swap_re ]]; then
        swap_used_mb="${BASH_REMATCH[1]}"
      fi
      if [ -n "$swap_total_mb" ] && [ -n "$swap_used_mb" ]; then
        # Hundredths-scaled integer math replaces the awk float probes:
        # _st = trunc(total*100), _su = trunc(used*100), so
        # _su*100/_st = used*100/total — truncation preserved from the
        # retired %d format (issue #98).
        local _st _su _si _sf
        _si="${swap_total_mb%%.*}"
        _sf=""
        case "$swap_total_mb" in *.*) _sf="${swap_total_mb#*.}" ;; esac
        _sf="${_sf%%[!0-9]*}00"
        case "$_si" in ""|*[!0-9]*) _si=0 ;; esac
        _st=$((10#${_si}${_sf:0:2}))
        _si="${swap_used_mb%%.*}"
        _sf=""
        case "$swap_used_mb" in *.*) _sf="${swap_used_mb#*.}" ;; esac
        _sf="${_sf%%[!0-9]*}00"
        case "$_si" in ""|*[!0-9]*) _si=0 ;; esac
        _su=$((10#${_si}${_sf:0:2}))
        if (( _st > 0 )); then
          swap_pct=$(( _su * 100 / _st ))
        fi
      fi
    fi
  else
    local swap_rec swap_total swap_used _skey
    swap_rec=$(perf_probe_swap 2>/dev/null || true)
    read -r _skey swap_used swap_total <<< "$swap_rec"
    swap_total="${swap_total:-0}"
    swap_used="${swap_used:-0}"
    if (( swap_total > 0 )); then
      swap_pct=$((swap_used * 100 / swap_total))
    fi
  fi

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_SWAP_PCT:-}" ]; then
    swap_pct="$DIAG_SWAP_PCT"
  fi

  # Get iowait (sampled on Linux to reflect current pressure)
  if is_linux && [ -f /proc/stat ]; then
    iowait_pct=$(get_linux_iowait_pct)
  elif is_macos; then
    # macOS proxy: high memory pressure + swap activity = likely thrashing
    # (pressure sampled via lib/perf_probes.sh; unreadable level falls
    # back to 1/normal as before).
    local pressure_rec pressure _pkey
    pressure_rec=$(perf_probe_mem_pressure 2>/dev/null || true)
    read -r _pkey pressure _ <<< "$pressure_rec"
    [ -z "$pressure" ] && pressure=1
    if [ "$pressure" = "4" ] && (( swap_pct > MDOCTOR_DIAG_PRESSURE_SWAP )); then
      iowait_pct=$MDOCTOR_DIAG_IOWAIT_HIGH  # Artificially high to trigger thrashing warning
    fi
  fi

  if (( swap_pct > MDOCTOR_DIAG_THRASH_SWAP && iowait_pct > MDOCTOR_DIAG_THRASH_IO )); then
    status_fail "SWAP THRASHING DETECTED: swap=${swap_pct}% iowait=${iowait_pct}%"
    add_diagnosis_action "critical" "System is thrashing between RAM and swap. This causes severe performance degradation. Free RAM immediately by closing applications or adding more memory."
    return 0
  elif (( swap_pct > MDOCTOR_DIAG_HEAVY_SWAP || iowait_pct > MDOCTOR_DIAG_HEAVY_IO )); then
    status_warn "Potential swap pressure: swap=${swap_pct}% iowait=${iowait_pct}%"
    add_diagnosis_action "warning" "System approaching swap thrashing conditions. Monitor memory usage and consider freeing RAM."
  fi
}

########################################
# CHECK: CPU + I/O Contention
########################################

check_cpu_io_contention() {
  local load1 cores iowait_pct=0

  if is_macos; then
    # macOS does not expose Linux-style CPU iowait; skip this correlation
    # rather than using unrelated memory counters as a disk I/O proxy.
    return 0
  else
    # Sampling: lib/perf_probes.sh (DIAG_LOADAVG / DIAG_CORES fixed
    # inputs are applied inside the probe, like every other consumer).
    local probe_load
    if ! probe_load=$(perf_probe_load 2>/dev/null); then
      return 0
    fi
    read -r load1 cores _ <<< "$probe_load"
    if [ -f /proc/stat ]; then
      iowait_pct=$(get_linux_iowait_pct)
    fi
  fi

  [ -z "$load1" ] && return 0
  [ -z "$cores" ] && return 0

  local load_int threshold
  # trunc(load1*100) via string decimal shift — same as the retired
  # awk %d (issue #98).
  local _li="${load1%%.*}" _lf=""
  case "$load1" in *.*) _lf="${load1#*.}" ;; esac
  _lf="${_lf%%[!0-9]*}00"
  case "$_li" in ""|*[!0-9]*) _li=0 ;; esac
  load_int=$((10#${_li}${_lf:0:2}))
  threshold=$((cores * 100))

  # High load + high iowait = CPU waiting on I/O
  if (( load_int > threshold && iowait_pct > MDOCTOR_DIAG_LOAD_IO )); then
    status_fail "CPU+I/O contention: load=${load1} (${cores} cores), iowait=${iowait_pct}%"
    add_diagnosis_action "critical" "System is CPU-bound AND I/O-bound. The bottleneck is likely disk performance. Consider SSD upgrade or reducing I/O workload."
  elif (( iowait_pct > MDOCTOR_DIAG_IO_ALONE )); then
    status_warn "I/O contention detected: iowait=${iowait_pct}%"
    add_diagnosis_action "warning" "Disk I/O is causing contention. Review disk operations with 'iotop'."
  fi
}

########################################
# CHECK: CPU User vs System Ratio (Linux)
########################################

check_cpu_user_sys() {
  local user nice system idle iowait irq softirq steal total user_pct sys_pct

  if ! is_linux || [ ! -f /proc/stat ]; then
    return 0
  fi

  # Read all CPU time fields from /proc/stat cpu line
  # Format: cpu  user nice system idle iowait irq softirq steal guest guest_nice
  read -r _ user nice system idle iowait irq softirq steal _ _ < <(head -1 /proc/stat 2>/dev/null)

  [ -z "$user" ] && return 0
  [ -z "$system" ] && return 0

  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  if (( total == 0 )); then
    return 0
  fi

  user_pct=$((user * 100 / total))
  sys_pct=$((system * 100 / total))

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_CPU_USER_PCT:-}" ]; then
    user_pct="$DIAG_CPU_USER_PCT"
  fi
  if [ -n "${DIAG_CPU_SYS_PCT:-}" ]; then
    sys_pct="$DIAG_CPU_SYS_PCT"
  fi

  if (( sys_pct > MDOCTOR_DIAG_SYS_HIGH )); then
    status_warn "CPU kernel-space usage: ${sys_pct}% (user=${user_pct}%)"
    add_diagnosis_action "warning" "High kernel-space CPU usage. Check for kernel modules, drivers, or system calls causing overhead."
  else
    status_ok "CPU user/sys ratio healthy (user=${user_pct}%, sys=${sys_pct}%)"
  fi
}

########################################
# MAIN: check_diagnose_performance
########################################

check_diagnose_performance() {
  echo "${BOLD}${BLUE}== Performance Diagnosis ==${RESET}"
  echo "${DIM}Running active diagnostic checks...${RESET}"
  echo

  ACTIONS=()
  ACTIONS_CRITICAL=()
  ACTIONS_WARNING=()
  # Reset the live-sample cache only; an explicit DIAG_LINUX_IOWAIT_PCT
  # test override is never cleared here (see get_linux_iowait_pct).
  _DIAG_IOWAIT_CACHED=""

  # ── CPU Diagnostics ──
  section_title "CPU Diagnostics"
  check_load_average
  check_top_cpu_consumers
  if is_linux; then
    check_cpu_user_sys
  fi

  # ── Memory Diagnostics ──
  section_title "Memory Diagnostics"
  check_memory_usage
  check_memory_pressure
  check_swap_usage

  # ── Disk I/O Diagnostics ──
  section_title "Disk I/O Diagnostics"
  check_disk_iowait
  check_disk_hotspots

  # ── Swap Thrashing Detection ──
  section_title "Swap Thrashing Detection"
  check_swap_thrashing

  # ── Zombie Process Detection ──
  section_title "Zombie Process Detection"
  check_zombie_processes

  # ── System Configuration ──
  section_title "System Configuration"
  check_fd_limits
  check_open_connections

  # ── Cross-Check Correlation ──
  section_title "Cross-Check Correlation"
  check_cpu_io_contention

  # ── Summary ──
  echo
  echo "${BOLD}${BLUE}== Diagnosis Summary ==${RESET}"
  echo

  local action_count=${#ACTIONS[@]}

  if (( action_count > 0 )); then
    echo "${RED}⚠ ${BOLD}${action_count} recommendation(s)${RESET}"
    echo

    # Print critical recommendations first, then warnings.
    local i=1
    local action
    set +u
    for action in "${ACTIONS_CRITICAL[@]}"; do
      echo "${RED}${i}. [critical] ${action}${RESET}"
      i=$((i + 1))
    done
    for action in "${ACTIONS_WARNING[@]}"; do
      echo "${YELLOW}${i}. [warning] ${action}${RESET}"
      i=$((i + 1))
    done
    set -u
  else
    echo "${GREEN}✅ ${BOLD}System healthy${RESET} — No bottlenecks detected."
  fi

  echo
  echo "${DIM}Diagnosis complete.${RESET}"
}
