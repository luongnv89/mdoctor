#!/usr/bin/env bash
#
# checks/diagnose_performance.sh
# Active performance diagnosis with bottleneck detection.
# Category: System | Risk: HIGH (active checks only, no modifications)
#
# Sources: lib/platform.sh, lib/common.sh
#

########################################
# CHECK: Load Average vs Core Count
########################################

check_load_average() {
  local cores load1 load5 load15 load_int threshold ratio_int
  local ratio_pct

  if is_macos; then
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    load5=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $3}')
    load15=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $4}')
  else
    cores=$(nproc 2>/dev/null || echo 4)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "")
    load5=$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo "")
    load15=$(awk '{print $3}' /proc/loadavg 2>/dev/null || echo "")
  fi

  if [ -z "$load1" ] || [ -z "$cores" ]; then
    status_info "Load average: unable to determine"
    return 0
  fi

  # Convert to integers (load1 * 100)
  load_int=$(awk -v l="$load1" 'BEGIN {printf "%d", l * 100}')
  threshold=$((cores * 100))
  ratio_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN {printf "%.0f", (l/c)*100}')

  if (( load_int > threshold * 2 )); then
    status_fail "Load average (${load1}) is >2x core count (${cores}) [${ratio_pct}% ratio]"
    add_action "System is severely overloaded. Run 'top' or 'htop' to identify runaway processes."
  elif (( load_int > threshold )); then
    status_warn "Load average (${load1}) exceeds core count (${cores}) [${ratio_pct}% ratio]"
    add_action "System load is high. Check running processes with 'top' or 'Activity Monitor'."
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
        add_action "Process '${name}' (PID ${pid}) is consuming ${pct}% CPU. Investigate or terminate with 'kill ${pid}'."
        high_count=$((high_count + 1))
      elif (( pct_int > 50 )); then
        status_warn "PID ${pid}: ${pct}% — ${name} (high consumer)"
        add_action "Process '${name}' (PID ${pid}) is consuming ${pct}% CPU. Consider monitoring or limiting its resource usage."
      fi
    fi
  done <<< "$top_cpu"

  if (( high_count == 0 )); then
    status_ok "No process exceeds 80% CPU usage."
  fi
}

########################################
# CHECK: CPU User vs System Ratio (Linux)
########################################

check_cpu_user_sys_ratio() {
  local user sys idle total user_pct

  if ! is_linux || [ ! -f /proc/stat ]; then
    return 0
  fi

  # Read first line of /proc/stat (cpu totals)
  user=$(awk '/^cpu / {print $2}' /proc/stat 2>/dev/null)
  sys=$(awk '/^cpu / {print $4}' /proc/stat 2>/dev/null)
  idle=$(awk '/^cpu / {print $5}' /proc/stat 2>/dev/null)

  [ -z "$user" ] && return 0
  [ -z "$sys" ] && return 0

  total=$((user + sys + idle))
  if (( total == 0 )); then
    return 0
  fi

  user_pct=$((user * 100 / total))
  local sys_pct=$((sys * 100 / total))

  if (( sys_pct > 40 )); then
    status_warn "CPU kernel-space usage: ${sys_pct}% (user=${user_pct}%, sys=${sys_pct}%)"
    add_action "High kernel-space CPU usage. Check for kernel modules, drivers, or system calls causing overhead."
  else
    status_ok "CPU user/sys ratio healthy (user=${user_pct}%, sys=${sys_pct}%)"
  fi
}

########################################
# CHECK: Memory Usage
########################################

check_memory_usage() {
  local total_kb used_kb avail_kb pct

  if is_macos; then
    # macOS: use sysctl for physical memory stats
    local page_size active_pages wired_pages free_pages total_bytes
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    active_pages=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
    wired_pages=$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$2); print $2+0}')

    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    local active_kb wired_kb free_kb
    active_kb=$(( ${active_pages:-0} * page_size / 1024 ))
    wired_kb=$(( ${wired_pages:-0} * page_size / 1024 ))
    free_kb=$(( ${free_pages:-0} * page_size / 1024 ))
    local used_kb=$((active_kb + wired_kb))
    total_kb=$((total_bytes / 1024))

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

  if (( pct > 95 )); then
    status_fail "Memory: ${pct}% used (${used_hr}/${total_hr}) — OOM risk!"
    add_action "Memory usage is critical. Close applications immediately to avoid out-of-memory crashes."
  elif (( pct > 85 )); then
    status_warn "Memory: ${pct}% used (${used_hr}/${total_hr}) — high usage"
    add_action "Memory usage is high. Review memory consumers with 'top' or 'Activity Monitor'."
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

    case "$pressure" in
      1) status_ok "Memory pressure: normal" ;;
      2) status_warn "Memory pressure: elevated"
         add_action "Memory pressure is elevated. Close unused applications to free RAM." ;;
      4) status_fail "Memory pressure: critical"
         add_action "Memory pressure is critical. Close applications immediately to prevent slowdowns." ;;
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
        if (( avail_pct < 5 )); then
          status_fail "Memory pressure: critical (${avail_pct}% available)"
          add_action "Memory pressure is critical. Close applications immediately."
        elif (( avail_pct < 15 )); then
          status_warn "Memory pressure: elevated (${avail_pct}% available)"
          add_action "Memory pressure is elevated. Close unused applications to free RAM."
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
      swap_in=$(vm_stat 2>/dev/null | awk '/Pages swapped in/ {gsub("\\.","",$3); print $3}')
      swap_out=$(vm_stat 2>/dev/null | awk '/Pages swapped out/ {gsub("\\.","",$3); print $3}')
      status_info "Swap activity: $((${swap_in:-0} + ${swap_out:-0})) pages total"
    else
      status_info "Swap: unavailable"
    fi
  else
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    swap_free=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    swap_used=$((swap_total - swap_free))

    if (( swap_total > 0 )); then
      pct=$((swap_used * 100 / swap_total))
      swap_hr=$(kb_to_human "$swap_used")
    else
      pct=0
      swap_hr="0 KB"
    fi

    if (( pct > 80 )); then
      status_fail "Swap: ${pct}% used (${swap_hr}/${swap_total} KB) — critical"
      add_action "Swap usage is critical. System is relying heavily on swap. Consider adding more RAM or reducing workload."
    elif (( pct > 50 )); then
      status_warn "Swap: ${pct}% used (${swap_hr}/${swap_total} KB)"
      add_action "Swap usage is high. Consider closing memory-intensive applications."
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
    # Read cpu line (index 0) — fields: user nice system idle iowait irq softirq steal
    local cpu_line user nice system idle iowait irq softirq steal
    read -r cpu_line user nice system idle iowait irq soft_irq steal _ _ _ < <(head -1 /proc/stat)
    local total=$((user + nice + system + idle + iowait + irq + soft_irq + steal))
    if (( total > 0 )); then
      iowait_pct=$((iowait * 100 / total))
    else
      iowait_pct=0
    fi
  elif is_macos; then
    # macOS: derive iowait proxy from vm_stat page faults
    local free_pages active_pages inactive_pages speculative_pages wired_pages
    local used_pages non_paging_pages page_size
    local reads writes

    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)

    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$2); print $2+0}')
    active_pages=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
    inactive_pages=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub("\\.","",$3); print $3+0}')
    speculative_pages=$(vm_stat 2>/dev/null | awk '/Pages speculative/ {gsub("\\.","",$3); print $3+0}')
    wired_pages=$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')

    # Page faults from vm_stat (not available directly; use paged stuff as proxy)
    local paged_total=$((free_pages + active_pages + inactive_pages + speculative_pages + wired_pages))
    if (( paged_total > 0 )); then
      # Approximate: high non-paging ratio suggests disk pressure
      local non_paging=$((wired_pages))
      iowait_pct=$((non_paging * 100 / paged_total))
    else
      iowait_pct=0
    fi
  else
    status_info "Disk I/O: unable to determine iowait"
    return 0
  fi

  if (( iowait_pct > 30 )); then
    status_fail "Disk I/O wait: ${iowait_pct}% — severe bottleneck"
    add_action "Disk I/O is a critical bottleneck. Check for heavy disk operations with 'iotop' or 'sudo iotop -o'."
  elif (( iowait_pct > 15 )); then
    status_warn "Disk I/O wait: ${iowait_pct}% — elevated"
    add_action "Disk I/O wait is elevated. Identify slow disk operations and consider SSD upgrade if on HDD."
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

  if [ -n "$root_disk_pct" ]; then
    if (( root_disk_pct > 95 )); then
      status_fail "Root disk usage: ${root_disk_pct}% — critical!"
      add_action "Root disk is nearly full. Remove unnecessary files immediately with 'mdoctor clean'."
    elif (( root_disk_pct > 85 )); then
      status_warn "Root disk usage: ${root_disk_pct}% — high"
      add_action "Root disk is nearly full. Consider cleanup with 'mdoctor clean' to reclaim space."
    else
      status_ok "Root disk usage: ${root_disk_pct}%"
    fi
  fi

  # Check for large temp/cache directories
  local large_dirs=""
  local dir_entry dir_size dir_hr
  for dir in /tmp "$HOME" /var/log /var/tmp; do
    [ ! -d "$dir" ] && continue
    dir_size=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    if [ -n "$dir_size" ] && (( dir_size > 1048576 )); then
      dir_hr=$(kb_to_human "$dir_size")
      large_dirs="${large_dirs}  ${dir}: ${dir_hr}\n"
    fi
  done

  if [ -n "$large_dirs" ]; then
    status_info "Large directories (>1 GB):"
    printf "%b" "$large_dirs"
  fi
}

########################################
# CHECK: Zombie Processes
########################################

check_zombie_processes() {
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
        add_action "Kill zombie parent processes: kill -HUP ${unique_parents}"
      fi
    else
      add_action "Found ${zombie_count} zombie process(es). These can be cleaned up by killing their parent process."
    fi
  else
    status_ok "No zombie processes."
  fi
}

########################################
# CHECK: File Descriptor Limits
########################################

check_fd_limits() {
  local fd_limit fd_open_pct fd_soft

  fd_soft=$(ulimit -n 2>/dev/null || echo 10240)
  fd_limit="$fd_soft"

  # Estimate open file descriptors
  local open_fds=0
  if is_macos; then
    open_fds=$(lsof 2>/dev/null | wc -l | awk '{print $1+0}')
    # Subtract the header line
    open_fds=$((open_fds > 1 ? open_fds - 1 : 0))
  else
    open_fds=$(find /proc -maxdepth 2 -name 'fd' -type d 2>/dev/null | wc -l | awk '{print $1+0}')
    open_fds=$((open_fds > 0 ? open_fds - 1 : 0))
  fi

  if (( fd_limit > 0 )); then
    fd_open_pct=$((open_fds * 100 / fd_limit))
  else
    fd_open_pct=0
  fi

  if (( fd_open_pct > 80 )); then
    status_fail "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
    add_action "File descriptor limit is nearly reached. Increase with 'ulimit -n <new_limit>' or adjust /etc/security/limits.conf."
  elif (( fd_open_pct > 50 )); then
    status_warn "File descriptors: ${open_fds}/${fd_limit} used (${fd_open_pct}%)"
    add_action "File descriptor usage is moderate. Monitor for potential limits on busy servers."
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
    conn_count=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
    conn_detail=$(netstat -an 2>/dev/null | grep -c LISTEN || echo 0)
  else
    conn_count=$(ss -tun 2>/dev/null | grep -c ESTAB || echo 0)
    conn_detail=$(ss -tun 2>/dev/null | grep -c LISTEN || echo 0)
  fi

  if (( conn_count > 5000 )); then
    status_fail "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail}) — critical"
    add_action "Unusually high number of open connections. Investigate with 'netstat -ant' or 'ss -tunap'."
  elif (( conn_count > 1000 )); then
    status_warn "Open connections: ${conn_count} ESTABLISHED (LISTEN: ${conn_detail})"
    add_action "High number of open connections. Monitor for potential connection leaks."
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
    local swap_total_raw
    swap_total_raw=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
    if [ -n "$swap_total_raw" ]; then
      # Parse "max = X Mb total used Y Mb virtual free Z Mb"
      swap_pct=$(echo "$swap_total_raw" | awk -F'total|used' '{if(NF>=3) gsub(/[^0-9]/,"",$2); print $2+0}')
    fi
  else
    local swap_total swap_used
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    swap_used=$(awk '/^SwapUsed:/ {print $2}' /proc/meminfo 2>/dev/null || \
                awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {print t-$2}' /proc/meminfo 2>/dev/null || echo 0)
    if (( swap_total > 0 )); then
      swap_pct=$((swap_used * 100 / swap_total))
    fi
  fi

  # Get iowait (reuse logic)
  if is_linux && [ -f /proc/stat ]; then
    local cpu_line user nice system idle iowait irq soft_irq steal total
    read -r cpu_line user nice system idle iowait irq soft_irq steal _ _ _ < <(head -1 /proc/stat)
    total=$((user + nice + system + idle + iowait + irq + soft_irq + steal))
    if (( total > 0 )); then
      iowait_pct=$((iowait * 100 / total))
    fi
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
    add_action "System is thrashing between RAM and swap. This causes severe performance degradation. Free RAM immediately by closing applications or adding more memory."
    return 0
  elif (( swap_pct > 30 || iowait_pct > 20 )); then
    status_warn "Potential swap pressure: swap=${swap_pct}% iowait=${iowait_pct}%"
    add_action "System approaching swap thrashing conditions. Monitor memory usage and consider freeing RAM."
  fi
}

########################################
# CHECK: CPU + I/O Contention
########################################

check_cpu_io_contention() {
  local load1 iowait_pct=0

  if is_macos; then
    load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    # Use the same proxy iowait as in check_disk_iowait
    local page_size active_pages wired_pages free_pages
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    active_pages=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3+0}')
    wired_pages=$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4+0}')
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$2); print $2+0}')
    local paged_total=$((active_pages + wired_pages + free_pages))
    if (( paged_total > 0 )); then
      iowait_pct=$((wired_pages * 100 / paged_total))
    fi
  else
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [ -f /proc/stat ]; then
      local user nice system idle iowait irq soft_irq steal total
      read -r _ user nice system idle iowait irq soft_irq steal _ _ _ < <(head -1 /proc/stat)
      total=$((user + nice + system + idle + iowait + irq + soft_irq + steal))
      if (( total > 0 )); then
        iowait_pct=$((iowait * 100 / total))
      fi
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
    add_action "System is CPU-bound AND I/O-bound. The bottleneck is likely disk performance. Consider SSD upgrade or reducing I/O workload."
  elif (( iowait_pct > 20 )); then
    status_warn "I/O contention detected: iowait=${iowait_pct}%"
    add_action "Disk I/O is causing contention. Review disk operations with 'iotop'."
  fi
}

########################################
# CHECK: CPU User vs System Ratio (Linux)
########################################

check_cpu_user_sys() {
  local user sys idle total user_pct sys_pct

  if ! is_linux || [ ! -f /proc/stat ]; then
    return 0
  fi

  user=$(awk '/^cpu / {print $2}' /proc/stat 2>/dev/null)
  sys=$(awk '/^cpu / {print $4}' /proc/stat 2>/dev/null)
  idle=$(awk '/^cpu / {print $5}' /proc/stat 2>/dev/null)

  [ -z "$user" ] && return 0
  [ -z "$sys" ] && return 0

  total=$((user + sys + idle))
  if (( total == 0 )); then
    return 0
  fi

  user_pct=$((user * 100 / total))
  sys_pct=$((sys * 100 / total))

  if (( sys_pct > 40 )); then
    status_warn "CPU kernel-space usage: ${sys_pct}% (user=${user_pct}%)"
    add_action "High kernel-space CPU usage. Check for kernel modules, drivers, or system calls causing overhead."
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

    # Sort by severity and display
    local i=1
    for action in "${ACTIONS[@]}"; do
      echo "${RED}${i}. ${action}${RESET}"
      i=$((i + 1))
    done
  else
    echo "${GREEN}✅ ${BOLD}System healthy${RESET} — No bottlenecks detected."
  fi

  echo
  echo "${DIM}Diagnosis complete.${RESET}"
}
