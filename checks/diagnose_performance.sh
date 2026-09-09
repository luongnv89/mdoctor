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

  if is_macos; then
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  else
    cores=$(nproc 2>/dev/null || echo 4)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "")
  fi

  if [ -z "$load1" ] || [ -z "$cores" ]; then
    status_info "Load average: unable to determine"
    return 0
  fi

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_LOADAVG:-}" ]; then
    load1="$DIAG_LOADAVG"
  fi
  if [ -n "${DIAG_CORES:-}" ]; then
    cores="$DIAG_CORES"
  fi

  # Convert to integers (load1 * 100)
  load_int=$(awk -v l="$load1" 'BEGIN {printf "%d", l * 100}')
  threshold=$((cores * 100))
  ratio_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN {printf "%.0f", (l/c)*100}')

  if (( load_int > threshold * 2 )); then
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
  local top_cpu line pid pct name
  local high_count=0

  # Task 2.5: guarded long-option ps; absent ps reports a skip.
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping top-CPU probe: ps not found."
    return 0
  fi

  if is_macos; then
    top_cpu=$(ps -arcwwxo "pid,%cpu,comm" 2>/dev/null | head -11 | tail -10)
  else
    top_cpu=$(ps -eo pid,%cpu,comm --sort=-%cpu 2>/dev/null | head -11 | tail -10)
  fi

  if [ -z "$top_cpu" ]; then
    status_info "Top CPU processes: unable to retrieve"
    return 0
  fi

  status_info "Top 10 CPU-consuming processes:"
  while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    pct=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')

    [ -z "$name" ] && continue

    if [ -n "$pct" ]; then
      local pct_int
      pct_int=$(awk -v p="$pct" 'BEGIN {printf "%d", p}')
      if (( pct_int > 80 )); then
        status_fail "PID ${pid}: ${pct}% — ${name} (critical consumer)"
        add_diagnosis_action "critical" "Process '${name}' (PID ${pid}) is consuming ${pct}% CPU. Investigate or terminate with 'kill ${pid}'."
        high_count=$((high_count + 1))
      elif (( pct_int > 50 )); then
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
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    active_pages=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
    wired_pages=$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')

    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
    local active_kb wired_kb
    active_kb=$(( ${active_pages:-0} * page_size / 1024 ))
    wired_kb=$(( ${wired_pages:-0} * page_size / 1024 ))
    local used_kb=$((active_kb + wired_kb))
    total_kb=$(( ${total_bytes:-0} / 1024 ))

    if (( total_kb > 0 )); then
      pct=$((used_kb * 100 / total_kb))
    else
      pct=0
    fi
  else
    # Linux: use /proc/meminfo
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
    used_kb=$(( ${total_kb:-0} - ${avail_kb:-0} ))

    if (( ${total_kb:-0} > 0 )); then
      pct=$((used_kb * 100 / total_kb))
    else
      pct=0
    fi
  fi

  # Format sizes
  local total_hr used_hr
  if (( total_kb >= 1048576 )); then
    total_hr=$(awk -v k="$total_kb" 'BEGIN {printf "%.1f GB", k/1048576}')
    used_hr=$(awk -v k="$used_kb" 'BEGIN {printf "%.1f GB", k/1048576}')
  elif (( total_kb >= 1024 )); then
    total_hr=$(awk -v k="$total_kb" 'BEGIN {printf "%.0f MB", k/1024}')
    used_hr=$(awk -v k="$used_kb" 'BEGIN {printf "%.0f MB", k/1024}')
  else
    total_hr="${total_kb} KB"
    used_hr="${used_kb} KB"
  fi

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_MEM_PCT:-}" ]; then
    pct="$DIAG_MEM_PCT"
  fi

  if (( pct > 95 )); then
    status_fail "Memory: ${pct}% used (${used_hr}/${total_hr}) — OOM risk!"
    add_diagnosis_action "critical" "Memory usage is critical. Close applications immediately to avoid out-of-memory crashes."
  elif (( pct > 85 )); then
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
  if is_macos; then
    local pressure
    pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "")

    # Fixed inputs for tests (see header comment).
    if [ -n "${DIAG_MEM_PRESSURE_LEVEL:-}" ]; then
      pressure="$DIAG_MEM_PRESSURE_LEVEL"
    fi

    case "$pressure" in
      1) status_ok "Memory pressure: normal" ;;
      2) status_warn "Memory pressure: elevated"
         add_diagnosis_action "warning" "Memory pressure is elevated. Close unused applications to free RAM." ;;
      4) status_fail "Memory pressure: critical"
         add_diagnosis_action "critical" "Memory pressure is critical. Close applications immediately to prevent slowdowns." ;;
      *) status_info "Memory pressure level: ${pressure:-unknown}" ;;
    esac
  else
    # Linux: MemAvailable ratio
    if [ -r /proc/meminfo ]; then
      local mem_total_kb mem_avail_kb avail_pct
      mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
      mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

      if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ] && (( mem_total_kb > 0 )); then
        avail_pct=$(( mem_avail_kb * 100 / mem_total_kb ))
        # Fixed inputs for tests (see header comment).
        if [ -n "${DIAG_MEM_AVAIL_PCT:-}" ]; then
          avail_pct="$DIAG_MEM_AVAIL_PCT"
        fi
        if (( avail_pct < 5 )); then
          status_fail "Memory pressure: critical (${avail_pct}% available)"
          add_diagnosis_action "critical" "Memory pressure is critical. Close applications immediately."
        elif (( avail_pct < 15 )); then
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
  local swap_total swap_free swap_used pct swap_hr

  if is_macos; then
    local swap_total_raw
    swap_total_raw=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
    if [ -n "$swap_total_raw" ]; then
      status_info "Swap: ${swap_total_raw}"

      # Try to get actual usage from vm_stat
      local swap_in swap_out
      swap_in=$(vm_stat 2>/dev/null | awk '/Pages swapped in/ {gsub("\\.","",$4); print $4}')
      swap_out=$(vm_stat 2>/dev/null | awk '/Pages swapped out/ {gsub("\\.","",$4); print $4}')
      status_info "Swap activity: $((${swap_in:-0} + ${swap_out:-0})) pages total"
    else
      status_info "Swap: unavailable"
    fi
  else
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)
    swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || true)
    swap_total="${swap_total:-0}"
    swap_free="${swap_free:-0}"
    swap_used=$((${swap_total:-0} - ${swap_free:-0}))

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

    if (( pct > 80 )); then
      status_fail "Swap: ${pct}% used (${swap_hr}/${swap_total} KB) — critical"
      add_diagnosis_action "critical" "Swap usage is critical. System is relying heavily on swap. Consider adding more RAM or reducing workload."
    elif (( pct > 50 )); then
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

  if (( iowait_pct > 30 )); then
    status_fail "Disk I/O wait: ${iowait_pct}% — severe bottleneck"
    add_diagnosis_action "critical" "Disk I/O is a critical bottleneck. Check for heavy disk operations with 'iotop' or 'sudo iotop -o'."
  elif (( iowait_pct > 15 )); then
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

  if is_macos; then
    [ -d /System/Volumes/Data ] && root_disk_pct=$(df -H /System/Volumes/Data 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
    [ -z "$root_disk_pct" ] && root_disk_pct=$(df -H / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
  else
    root_disk_pct=$(df -H / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
  fi

  # Fixed inputs for tests (see header comment).
  if [ -n "${DIAG_DISK_PCT:-}" ]; then
    root_disk_pct="$DIAG_DISK_PCT"
  fi

  if [ -n "$root_disk_pct" ]; then
    if (( root_disk_pct > 95 )); then
      status_fail "Root disk usage: ${root_disk_pct}% — critical!"
      add_diagnosis_action "critical" "Root disk is nearly full. Remove unnecessary files immediately with 'mdoctor clean'."
    elif (( root_disk_pct > 85 )); then
      status_warn "Root disk usage: ${root_disk_pct}% — high"
      add_diagnosis_action "warning" "Root disk is nearly full. Consider cleanup with 'mdoctor clean' to reclaim space."
    else
      status_ok "Root disk usage: ${root_disk_pct}%"
    fi
  fi

  # Check for large temp/cache directories (fast: only scan known small dirs)
  # Skip deep home directory scans — they are too slow for a diagnostic check
  local large_dirs=""
  local dir_size dir_hr
  local -a fast_dirs=("/tmp" /var/log /var/tmp)
  for dir in "${fast_dirs[@]}"; do
    [ ! -d "$dir" ] && continue
    dir_size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    if [ -n "$dir_size" ] && (( dir_size > 1048576 )); then
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
  if ! command -v ps >/dev/null 2>&1; then
    status_info "Skipping zombie probe: ps not found."
    return 0
  fi

  local zombie_count
  zombie_count=$(ps -eo stat 2>/dev/null | grep -c '^Z' || true)

  if (( zombie_count > 0 )); then
    status_warn "Zombie processes: ${zombie_count}"

    local zombie_list parent_pids unique_parents
    zombie_list=$(ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/ {print $1, $2, $4}')

    if [ -n "$zombie_list" ]; then
      parent_pids=""
      while IFS= read -r zline; do
        local zpid zppid zname
        zpid=$(echo "$zline" | awk '{print $1}')
        zppid=$(echo "$zline" | awk '{print $2}')
        zname=$(echo "$zline" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')
        status_info "  PID ${zpid} → Parent ${zppid} — ${zname}"
        if [ -n "$parent_pids" ]; then
          parent_pids="${parent_pids} ${zppid}"
        else
          parent_pids="${zppid}"
        fi
      done <<< "$zombie_list"

      unique_parents=$(echo "$parent_pids" | tr ' ' '\n' | sort -un | tr '\n' ' ' | sed 's/ *$//')
      if [ -n "$unique_parents" ]; then
        add_diagnosis_action "warning" "Kill zombie parent processes: kill -HUP ${unique_parents}"
      fi
    else
      add_diagnosis_action "warning" "Found ${zombie_count} zombie process(es). These can be cleaned up by killing their parent process."
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
    open_files=$(sysctl -n kern.num_files 2>/dev/null | tr -d '\n\r ' || true)
    fd_limit=$(sysctl -n kern.maxfiles 2>/dev/null | awk '{print $1}')
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
    file_nr=$(cat /proc/sys/fs/file-nr 2>/dev/null)
    open_fds=$(echo "$file_nr" | awk '{print $1+0}')
    fd_limit=$(echo "$file_nr" | awk '{print $3+0}')
    if (( ${fd_limit:-0} <= 0 )) && [ -f /proc/sys/fs/file-max ]; then
      fd_limit=$(cat /proc/sys/fs/file-max 2>/dev/null | tr -d '\n\r ')
    fi
  fi

  fd_limit=${fd_limit:-0}
  if (( fd_limit > 0 )); then
    fd_open_pct=$((open_fds * 100 / fd_limit))
  else
    fd_open_pct=0
  fi

  if (( fd_open_pct > 80 )); then
    status_fail "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
    add_diagnosis_action "critical" "File descriptor limit is nearly reached. Increase with 'ulimit -n <new_limit>' or adjust /etc/security/limits.conf."
  elif (( fd_open_pct > 50 )); then
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

  if is_macos; then
    conn_count=$(netstat -an 2>/dev/null | grep -c ESTABLISHED 2>/dev/null || true)
    conn_count=$(echo "$conn_count" | tr -d '\n\r ')
    conn_detail=$(netstat -an 2>/dev/null | grep -c LISTEN 2>/dev/null || true)
    conn_detail=$(echo "$conn_detail" | tr -d '\n\r ')
  else
    # Task 2.5: guarded ss; absent ss reports a skip and counts as zero.
    if ! command -v ss >/dev/null 2>&1; then
      status_info "Skipping connection-count probe: ss not found."
      conn_count=0
      conn_detail=0
    else
      conn_count=$(ss -tun 2>/dev/null | grep -c ESTAB 2>/dev/null || true)
      conn_count=$(echo "$conn_count" | tr -d '\n\r ')
      conn_detail=$(ss -tun 2>/dev/null | grep -c LISTEN 2>/dev/null || true)
      conn_detail=$(echo "$conn_detail" | tr -d '\n\r ')
    fi
  fi

  if (( conn_count > 5000 )); then
    status_fail "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail}) — critical"
    add_diagnosis_action "critical" "Unusually high number of open connections. Investigate with 'netstat -ant' or 'ss -tunap'."
  elif (( conn_count > 1000 )); then
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

  # Get swap usage
  if is_macos; then
    local swap_total_raw swap_total_mb swap_used_mb
    swap_total_raw=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
    if [ -n "$swap_total_raw" ]; then
      # Format varies by macOS version: "0.00M" or "0.00Mb".
      swap_total_mb=$(echo "$swap_total_raw" | sed -n 's/.*total = \([0-9.]*\)[Mm][Bb]*.*/\1/p' | tr -d ' ')
      swap_used_mb=$(echo "$swap_total_raw" | sed -n 's/.*used = \([0-9.]*\)[Mm][Bb]*.*/\1/p' | tr -d ' ')
      if [ -n "$swap_total_mb" ] && [ -n "$swap_used_mb" ] && awk -v t="$swap_total_mb" 'BEGIN {exit !(t+0 > 0)}' 2>/dev/null; then
        swap_pct=$(awk -v u="$swap_used_mb" -v t="$swap_total_mb" 'BEGIN {printf "%d", u*100/t}')
      fi
    fi
  else
    local swap_total swap_used
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)
    swap_used=$(awk 'BEGIN{t=0} /^SwapTotal:/{t=$2} /^SwapFree:/{print t-$2}' /proc/meminfo 2>/dev/null || true)
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
    local pressure
    pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)
    if [ "$pressure" = "4" ] && (( swap_pct > 20 )); then
      iowait_pct=30  # Artificially high to trigger thrashing warning
    fi
  fi

  if (( swap_pct > 50 && iowait_pct > 10 )); then
    status_fail "SWAP THRASHING DETECTED: swap=${swap_pct}% iowait=${iowait_pct}%"
    add_diagnosis_action "critical" "System is thrashing between RAM and swap. This causes severe performance degradation. Free RAM immediately by closing applications or adding more memory."
    return 0
  elif (( swap_pct > 30 || iowait_pct > 20 )); then
    status_warn "Potential swap pressure: swap=${swap_pct}% iowait=${iowait_pct}%"
    add_diagnosis_action "warning" "System approaching swap thrashing conditions. Monitor memory usage and consider freeing RAM."
  fi
}

########################################
# CHECK: CPU + I/O Contention
########################################

check_cpu_io_contention() {
  local load1 iowait_pct=0

  if is_macos; then
    # macOS does not expose Linux-style CPU iowait; skip this correlation
    # rather than using unrelated memory counters as a disk I/O proxy.
    return 0
  else
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [ -f /proc/stat ]; then
      iowait_pct=$(get_linux_iowait_pct)
    fi
  fi

  [ -z "$load1" ] && return 0

  local cores load_int threshold
  if is_macos; then
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
  else
    cores=$(nproc 2>/dev/null || echo 4)
  fi
  load_int=$(awk -v l="$load1" 'BEGIN {printf "%d", l * 100}')
  threshold=$((cores * 100))

  # High load + high iowait = CPU waiting on I/O
  if (( load_int > threshold && iowait_pct > 15 )); then
    status_fail "CPU+I/O contention: load=${load1} (${cores} cores), iowait=${iowait_pct}%"
    add_diagnosis_action "critical" "System is CPU-bound AND I/O-bound. The bottleneck is likely disk performance. Consider SSD upgrade or reducing I/O workload."
  elif (( iowait_pct > 20 )); then
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

  if (( sys_pct > 40 )); then
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
