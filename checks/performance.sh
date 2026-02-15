#!/usr/bin/env bash
#
# checks/performance.sh
# Performance & memory analysis (read-only, SAFE)
# Category: System
#

check_performance() {
  step "Performance & Memory"

  # Memory pressure level
  local pressure
  pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "")
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

  # Swap usage
  local swap_used
  swap_used=$(sysctl -n vm.swapusage 2>/dev/null | awk -F'= ' '{for(i=1;i<=NF;i++) if($i~/used/) print $i}' | awk '{print $1}')
  if [ -z "$swap_used" ]; then
    swap_used=$(sysctl -n vm.swapusage 2>/dev/null | grep -o 'used = [0-9.]*M' | awk '{print $3}' || echo "")
  fi
  local swap_total
  swap_total=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
  if [ -n "$swap_total" ]; then
    status_info "Swap: ${swap_total}"
  fi

  # Top 5 CPU-consuming processes
  local top_cpu
  top_cpu=$(ps -arcwwxo "pid,%cpu,comm" 2>/dev/null | head -6 | tail -5)
  if [ -n "$top_cpu" ]; then
    status_info "Top CPU processes:"
    local line
    while IFS= read -r line; do
      local pid pct name
      pid=$(echo "$line" | awk '{print $1}')
      pct=$(echo "$line" | awk '{print $2}')
      name=$(echo "$line" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')
      if [ -n "$name" ]; then
        status_info "  PID ${pid}: ${pct}% — ${name}"
      fi
    done <<< "$top_cpu"
  fi

  # Top 5 memory-consuming processes
  local top_mem
  top_mem=$(ps -amcwwxo "pid,rss,comm" 2>/dev/null | head -6 | tail -5)
  if [ -n "$top_mem" ]; then
    status_info "Top memory processes:"
    local line
    while IFS= read -r line; do
      local pid rss_kb name mem_hr
      pid=$(echo "$line" | awk '{print $1}')
      rss_kb=$(echo "$line" | awk '{print $2}')
      name=$(echo "$line" | awk '{$1=""; $2=""; print}' | sed 's/^ *//')
      if [ -n "$name" ] && [ -n "$rss_kb" ] && (( rss_kb > 0 )); then
        if (( rss_kb >= 1048576 )); then
          mem_hr=$(awk -v kb="$rss_kb" 'BEGIN {printf "%.1f GB", kb/1048576}')
        elif (( rss_kb >= 1024 )); then
          mem_hr=$(awk -v kb="$rss_kb" 'BEGIN {printf "%.0f MB", kb/1024}')
        else
          mem_hr="${rss_kb} KB"
        fi
        status_info "  PID ${pid}: ${mem_hr} — ${name}"
      fi
    done <<< "$top_mem"
  fi

  # Zombie processes
  local zombie_count
  # shellcheck disable=SC2009
  zombie_count=$(ps -eo stat 2>/dev/null | grep -c '^Z' || true)
  if (( zombie_count > 0 )); then
    status_warn "Zombie processes: ${zombie_count}"
    # List zombie processes with their parent PIDs
    local zombie_list
    zombie_list=$(ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/ {print $1, $2, $4}')
    if [ -n "$zombie_list" ]; then
      status_info "Zombie process details (PID → Parent PID — Command):"
      local parent_pids=""
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
      # Deduplicate parent PIDs
      local unique_parents
      unique_parents=$(echo "$parent_pids" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ *$//')
      if [ -n "$unique_parents" ]; then
        add_action "Found ${zombie_count} zombie process(es). Kill their parent process(es) to clean up: kill -HUP ${unique_parents}"
      fi
    else
      add_action "Found ${zombie_count} zombie process(es). These are defunct processes that can be cleaned up by killing their parent."
    fi
  else
    status_ok "No zombie processes."
  fi

  # Load average assessment
  local cores load1
  cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
  load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  if [ -n "$load1" ] && [ -n "$cores" ]; then
    local load_int
    load_int=$(awk -v l="$load1" 'BEGIN {printf "%d", l * 100}')
    local threshold=$((cores * 100))
    if (( load_int > threshold )); then
      status_warn "Load average (${load1}) exceeds CPU core count (${cores})"
      add_action "System load is high. Check running processes with 'top' or 'Activity Monitor'."
    else
      status_ok "Load average (${load1}) within normal range for ${cores} cores."
    fi
  fi
}
