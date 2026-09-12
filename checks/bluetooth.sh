#!/usr/bin/env bash
#
# checks/bluetooth.sh
# Bluetooth status check (read-only, SAFE)
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
check_bluetooth() {
  step "Bluetooth Status"

  local bt_info
  bt_info=$(system_profiler SPBluetoothDataType 2>/dev/null || true)

  if [ -z "$bt_info" ]; then
    status_info "Bluetooth information not available."
    return 0
  fi

  # Bluetooth power state — first line containing "State:" supplies the
  # value after the first ': ' separator (same split the retired
  # echo|awk -F': ' {print $2; exit}|tr pipeline produced, issue #98).
  local bt_state="" _btline _btf2
  while IFS= read -r _btline; do
    case "$_btline" in
      *State:*)
        case "$_btline" in
          *": "*)
            _btf2="${_btline#*: }"
            _btf2="${_btf2%%: *}"
            bt_state="${_btf2//[[:space:]]/}"
            ;;
        esac
        break
        ;;
    esac
  done <<< "$bt_info"
  if [ -z "$bt_state" ]; then
    # Try alternative: defaults read
    bt_state=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo "")
    if [ "$bt_state" = "1" ]; then
      bt_state="On"
    elif [ "$bt_state" = "0" ]; then
      bt_state="Off"
    fi
  fi

  if [ -n "$bt_state" ]; then
    if [ "$bt_state" = "On" ] || [ "$bt_state" = "Attivo" ]; then
      status_ok "Bluetooth: On"
    else
      status_info "Bluetooth: ${bt_state}"
    fi
  fi

  # Bluetooth hardware version / chipset — same first-': '-split rule.
  local bt_chipset=""
  while IFS= read -r _btline; do
    case "$_btline" in
      *Chipset:*)
        case "$_btline" in
          *": "*)
            _btf2="${_btline#*: }"
            bt_chipset="${_btf2%%: *}"
            ;;
        esac
        break
        ;;
    esac
  done <<< "$bt_info"
  if [ -n "$bt_chipset" ]; then
    status_info "Bluetooth chipset: ${bt_chipset}"
  fi

  # Connected devices
  # The output has sections "Connected:" and "Not Connected:" with device names
  # as indented headers (e.g. "          MX Anywhere 3S:") followed by properties.
  # We parse between "Connected:" and "Not Connected:" sections.
  #
  # Single pass, zero forks (issue #98): the old per-device echo|awk
  # look-ahead for "Minor Type:" is replaced by a pending slot — a device
  # header goes pending, the next "Minor Type:" line attaches to it, and
  # the next same-indent header flushes it bare. That mirrors the retired
  # awk's stop-at-next-header window.
  local in_connected=0
  local connected_count=0
  local device_lines=""
  local line trimmed
  local pending_dev=""

  while IFS= read -r line; do
    # Match the top-level "Connected:" section header (6 leading spaces)
    if [ "$line" = "      Connected:" ]; then
      in_connected=1
      continue
    fi
    if (( in_connected == 1 )); then
      # Stop at "Not Connected:" or any other top-level section
      # (6 leading spaces then a capital letter — the old grep -E
      # '^      [A-Z]').
      case "$line" in
        "      "[A-Z]*)
          in_connected=0
          continue
          ;;
      esac
      # Device names are indented with ~10 spaces and end with ":"
      # but are NOT property lines (which contain ": " with a value).
      trimmed="${line#"${line%%[![:space:]]*}"}"
      # Device header: "DeviceName:" (at least one char then ':' —
      # the old grep -E '^.+:$'). Checked before the Minor Type
      # property arm so a valueless "Minor Type:" still counts as a
      # header exactly like the retired grep.
      case "$trimmed" in
        ?*:)
          # A pending device reached the next same-indent header with no
          # Minor Type — emit it bare, like the awk look-ahead timeout.
          if [ -n "$pending_dev" ]; then
            device_lines="${device_lines}${pending_dev}"$'\n'
            connected_count=$((connected_count + 1))
          fi
          pending_dev="${trimmed%:}"
          continue
          ;;
      esac
      # "Minor Type:" property line — attach to the pending device;
      # the retired awk sub() stripped only trailing spaces after the
      # colon, so the ltrim below matches on ' ' rather than [[:space:]].
      case "$line" in
        *"Minor Type:"*)
          if [ -n "$pending_dev" ]; then
            local _mt="${line#*Minor Type:}"
            _mt="${_mt#"${_mt%%[! ]*}"}"
            if [ -n "$_mt" ]; then
              device_lines="${device_lines}${pending_dev} (${_mt})"$'\n'
            else
              device_lines="${device_lines}${pending_dev}"$'\n'
            fi
            pending_dev=""
            connected_count=$((connected_count + 1))
          fi
          ;;
      esac
    fi
  done <<< "$bt_info"
  # Flush a trailing pending device.
  if [ -n "$pending_dev" ]; then
    device_lines="${device_lines}${pending_dev}"$'\n'
    connected_count=$((connected_count + 1))
  fi

  if (( connected_count > 0 )); then
    status_info "Connected Bluetooth devices: ${connected_count}"
    local dline
    while IFS= read -r dline; do
      # if/fi (not [ -n ] &&) so a trailing empty line can't make the
      # loop — and the whole check — return non-zero.
      if [ -n "$dline" ]; then
        status_info "  ${dline}"
      fi
    done <<< "$device_lines"
  else
    status_info "No Bluetooth devices connected."
  fi
}
