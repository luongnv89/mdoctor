#!/usr/bin/env bash
#
# checks/usb.sh
# USB devices audit (read-only, SAFE)
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
check_usb() {
  step "USB Devices"

  local usb_info
  usb_info=$(system_profiler SPUSBDataType 2>/dev/null || true)

  if [ -z "$usb_info" ]; then
    status_info "No USB information available."
    return 0
  fi

  # Count connected USB devices (lines containing product name pattern)
  local device_count=0
  local high_power_count=0
  local device_list=""
  local line current_device

  current_device=""

  # Case-insensitive skip set kept in a variable — Bash 3.2's =~ parser
  # treats inline quoting differently (issue #98: replaces two
  # echo|grep pipelines per line).
  local skip_re='[Uu][Ss][Bb] [Bb]us|[Hh]ost [Cc]ontroller|[Hh][Uu][Bb]'
  while IFS= read -r line; do
    # Device name lines are indented and end with ":"
    local trimmed
    trimmed="${line#"${line%%[![:space:]]*}"}"

    # Capture device names (non-Apple hub entries that have a colon at
    # end): starts with a letter, ends with ':' — the old
    # grep -E '^[A-Za-z].*:$' — and contains no bus/controller/hub word.
    if [[ "$trimmed" =~ ^[A-Za-z].*:$ ]] && [[ ! "$trimmed" =~ $skip_re ]]; then
      current_device="${trimmed%:}"
      device_count=$((device_count + 1))
      if [ -n "$device_list" ]; then
        device_list="${device_list}, ${current_device}"
      else
        device_list="${current_device}"
      fi
    fi

    # Check power draw (in mA) — value after the 'Current Available
    # (mA): ' label with non-digits stripped, same as the retired
    # awk -F': ' gsub(/[^0-9]/) extraction.
    local power_ma=""
    case "$line" in
      *"Current Available (mA): "*)
        local _pv="${line#*"Current Available (mA): "}"
        power_ma="${_pv//[!0-9]/}"
        ;;
    esac
    if [ -n "$power_ma" ] && (( power_ma > 500 )); then
      high_power_count=$((high_power_count + 1))
    fi
  done <<< "$usb_info"

  if (( device_count > 0 )); then
    status_ok "Connected USB devices: ${device_count}"
    if [ -n "$device_list" ]; then
      status_info "Devices: ${device_list}"
    fi
  else
    status_info "No USB devices connected."
  fi

  if (( high_power_count > 0 )); then
    status_info "USB ports providing high power (>500mA): ${high_power_count}"
  fi
}
