#!/usr/bin/env bash
#
# checks/hardware.sh
# Hardware overview & thermals (read-only, SAFE)
# Category: Hardware
#

check_hardware() {
  step "Hardware Overview & Thermals"

  if is_macos; then
    # Model name
    local model_name
    model_name=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}')
    if [ -n "$model_name" ]; then
      status_info "Model: ${model_name}"
    fi

    # CPU
    local cpu_brand
    cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    status_info "CPU: ${cpu_brand}"

    # Core count
    local physical_cores logical_cores
    physical_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "?")
    logical_cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo "?")
    status_info "Cores: ${physical_cores} physical, ${logical_cores} logical"

    # Total RAM
    local total_mem total_gb
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    if (( total_mem > 0 )); then
      total_gb=$(awk -v m="$total_mem" 'BEGIN {printf "%.0f", m/1073741824}')
      status_info "Memory: ${total_gb} GB"
    fi

    # Thermal throttling level
    local thermal_level
    thermal_level=$(sysctl -n machdep.xcpm.cpu_thermal_level 2>/dev/null || echo "")
    if [ -n "$thermal_level" ]; then
      if (( thermal_level > 0 )); then
        status_warn "CPU thermal throttling level: ${thermal_level} (elevated)"
        add_action "CPU is thermally throttling (level ${thermal_level}). Check ventilation and running processes."
      else
        status_ok "CPU thermal throttling: none (level 0)"
      fi
    else
      status_info "CPU thermal level: not available (Apple Silicon or unsupported)"
    fi

    # CPU frequency (Intel only)
    local cpu_freq
    cpu_freq=$(sysctl -n hw.cpufrequency 2>/dev/null || echo "")
    if [ -n "$cpu_freq" ] && (( cpu_freq > 0 )); then
      local freq_ghz
      freq_ghz=$(awk -v f="$cpu_freq" 'BEGIN {printf "%.2f", f/1000000000}')
      status_info "CPU base frequency: ${freq_ghz} GHz"
    fi
  else
    # Linux: /proc/cpuinfo, /proc/meminfo, /sys/class/thermal
    local cpu_model
    cpu_model=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Unknown")
    status_info "CPU: ${cpu_model}"

    local physical_cores logical_cores
    logical_cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "?")
    physical_cores=$(awk '/^core id/ {print $NF}' /proc/cpuinfo 2>/dev/null | sort -u | wc -l | tr -d ' ')
    [ "$physical_cores" = "0" ] && physical_cores="$logical_cores"
    status_info "Cores: ${physical_cores} physical, ${logical_cores} logical"

    local total_mem_kb total_gb
    total_mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    if (( total_mem_kb > 0 )); then
      total_gb=$(awk -v kb="$total_mem_kb" 'BEGIN {printf "%.0f", kb/1048576}')
      status_info "Memory: ${total_gb} GB"
    fi

    # Thermal zones
    local tz_dir="/sys/class/thermal"
    if [ -d "$tz_dir" ]; then
      local tz
      for tz in "$tz_dir"/thermal_zone*/temp; do
        [ -r "$tz" ] || continue
        local temp_milli tz_name temp_c
        temp_milli=$(cat "$tz" 2>/dev/null || echo 0)
        tz_name=$(cat "$(dirname "$tz")/type" 2>/dev/null || echo "unknown")
        temp_c=$((temp_milli / 1000))
        if (( temp_c > 85 )); then
          status_warn "Thermal zone ${tz_name}: ${temp_c}C (high)"
          add_action "CPU temperature is high (${temp_c}C). Check cooling and running processes."
        elif (( temp_c > 0 )); then
          status_ok "Thermal zone ${tz_name}: ${temp_c}C"
        fi
        break  # show first zone only
      done
    fi
  fi
}
