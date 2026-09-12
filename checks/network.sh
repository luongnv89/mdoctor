#!/usr/bin/env bash
#
# checks/network.sh
# Network connectivity & diagnostics (read-only, SAFE)
# Category: System
#

# ping_host HOST — one ping packet with a platform-correct per-packet
# timeout (Task 2.5). macOS `ping -W` is MILLISECONDS, Linux `ping -W`
# is SECONDS: the old shared `-W 1000` waited 1000s per packet on Linux.

# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
ping_host() {
  if is_macos; then
    ping -c 1 -W 1000 "$@"
  else
    ping -c 1 -W 1 "$@"
  fi
}

check_network() {
  step "Network Diagnostics"

  # Basic connectivity (Task 2.5: guarded; absent ping reports a skip,
  # never an error).
  if ! command -v ping >/dev/null 2>&1; then
    status_info "Skipping connectivity probe: ping not found."
  else
    if ping_host 1.1.1.1 >/dev/null 2>&1; then
      status_ok "Can reach the internet (ping 1.1.1.1 succeeded)."
    else
      status_warn "Ping to 1.1.1.1 failed."
      add_action "Check network connectivity or firewall rules (ping to 1.1.1.1 fails)."
    fi

    if ping_host github.com >/dev/null 2>&1; then
      status_ok "Can reach github.com."
    else
      status_warn "Cannot reach github.com."
      add_action "Check DNS / network configuration: unable to reach github.com."
    fi
  fi

  # DNS resolution speed
  local dns_start dns_end dns_ms
  dns_start=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()' 2>/dev/null || echo "")
  if ! command -v nslookup >/dev/null 2>&1; then
    status_info "Skipping DNS timing probe: nslookup not found."
  elif [ -n "$dns_start" ]; then
    nslookup google.com >/dev/null 2>&1
    dns_end=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()' 2>/dev/null || echo "")
    if [ -n "$dns_end" ]; then
      dns_ms=$(awk -v s="$dns_start" -v e="$dns_end" 'BEGIN {printf "%.0f", (e-s)*1000}')
      if (( dns_ms > 500 )); then
        status_warn "DNS resolution: ${dns_ms}ms (slow, >500ms)"
        add_action "DNS resolution is slow (${dns_ms}ms). Consider switching to faster DNS (1.1.1.1 or 8.8.8.8)."
      else
        status_ok "DNS resolution: ${dns_ms}ms"
      fi
    fi
  fi

  # Active network service — in-shell field splits replace the
  # route/ip|awk extractions (issue #98).
  local active_service=""
  if is_macos; then
    local _rt_out _rtl _rk _rv
    _rt_out=$(route get default 2>/dev/null || true)
    while IFS= read -r _rtl; do
      read -r _rk _rv _ <<< "$_rtl"
      if [ "$_rk" = "interface:" ]; then
        active_service="$_rv"
      fi
    done <<< "$_rt_out"
  else
    local _ipr _i1 _i2 _i3 _i4
    _ipr=$(ip route show default 2>/dev/null || true)
    # First row only — the retired awk '{print $5; exit}'.
    read -r _i1 _i2 _i3 _i4 active_service _ <<< "$_ipr"
  fi
  if [ -n "$active_service" ]; then
    status_info "Active network interface: ${active_service}"

    # Local IP address on the active interface
    local local_ip=""
    if is_macos; then
      local_ip=$(ipconfig getifaddr "$active_service" 2>/dev/null || echo "")
    else
      local _ia_out _ial _iaf1 _iaf2
      _ia_out=$(ip -4 addr show "$active_service" 2>/dev/null || true)
      while IFS= read -r _ial; do
        case "$_ial" in
          *"inet "*)
            read -r _iaf1 _iaf2 _ <<< "$_ial"
            local_ip="${_iaf2%%/*}"
            break
            ;;
        esac
      done <<< "$_ia_out"
    fi
    if [ -n "$local_ip" ]; then
      status_info "Local IP address: ${local_ip}"
    fi
  fi

  # Public IP address
  local public_ip
  public_ip=$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "")
  if [ -n "$public_ip" ]; then
    status_info "Public IP address: ${public_ip}"
  fi

  # Wi-Fi signal strength
  if is_macos; then
    local airport_path="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    if [ -x "$airport_path" ]; then
      local wifi_info
      wifi_info=$("$airport_path" -I 2>/dev/null || true)
      if [ -n "$wifi_info" ] && [[ "$wifi_info" != *"AirPort: Off"* ]]; then
        # Keyed field extraction in-shell — one pass, no echo|awk (issue
        # #98). agrCtl* fields split on whitespace like awk's default FS;
        # SSID splits on ': ' like the retired -F': ' $2.
        local rssi="" noise="" ssid="" wline _wv
        while IFS= read -r wline; do
          case "$wline" in
            *agrCtlRSSI:*)
              _wv="${wline#*agrCtlRSSI:}"
              rssi="${_wv#"${_wv%%[![:space:]]*}"}"
              rssi="${rssi%%[[:space:]]*}"
              ;;
            *agrCtlNoise:*)
              _wv="${wline#*agrCtlNoise:}"
              noise="${_wv#"${_wv%%[![:space:]]*}"}"
              noise="${noise%%[[:space:]]*}"
              ;;
            *[[:space:]]SSID:*)
              ssid="${wline#*: }"
              ssid="${ssid%%: *}"
              ;;
          esac
        done <<< "$wifi_info"

        if [ -n "$ssid" ]; then
          status_info "Wi-Fi network: ${ssid}"
        fi

        if [ -n "$rssi" ] && [ -n "$noise" ]; then
          local snr=$((rssi - noise))
          if (( snr < 15 )); then
            status_warn "Wi-Fi signal: RSSI ${rssi}dBm, Noise ${noise}dBm, SNR ${snr}dB (poor, <15dB)"
            add_action "Wi-Fi signal quality is poor (SNR: ${snr}dB). Move closer to router or reduce interference."
          elif (( snr < 25 )); then
            status_ok "Wi-Fi signal: RSSI ${rssi}dBm, Noise ${noise}dBm, SNR ${snr}dB (fair)"
          else
            status_ok "Wi-Fi signal: RSSI ${rssi}dBm, Noise ${noise}dBm, SNR ${snr}dB (good)"
          fi
        fi
      fi
    fi
  else
    # Linux: Wi-Fi via iw or iwconfig
    if command -v iw >/dev/null 2>&1 && [ -n "$active_service" ]; then
      local wifi_info
      wifi_info=$(iw dev "$active_service" link 2>/dev/null || true)
      if [ -n "$wifi_info" ] && [[ "$wifi_info" != *"Not connected"* ]]; then
        # Same in-shell keyed extraction as the airport arm (issue #98).
        local ssid="" signal="" wline _wv
        while IFS= read -r wline; do
          case "$wline" in
            *SSID:*)
              ssid="${wline#*: }"
              ssid="${ssid%%: *}"
              ;;
            *signal:*)
              _wv="${wline#*signal:}"
              signal="${_wv#"${_wv%%[![:space:]]*}"}"
              signal="${signal%%[[:space:]]*}"
              ;;
          esac
        done <<< "$wifi_info"
        [ -n "$ssid" ] && status_info "Wi-Fi network: ${ssid}"
        if [ -n "$signal" ]; then
          local sig_val="${signal%% *}"
          if (( sig_val < -75 )); then
            status_warn "Wi-Fi signal: ${signal} dBm (weak)"
          else
            status_ok "Wi-Fi signal: ${signal} dBm"
          fi
        fi
      fi
    fi
  fi

  # VPN connection status
  if is_macos; then
    local vpn_active
    vpn_active=$(scutil --nc list 2>/dev/null | grep -c "Connected" || true)
    if (( vpn_active > 0 )); then
      status_info "VPN: ${vpn_active} connection(s) active"
    fi
  else
    # Linux: check for tun/tap interfaces or active VPN connections
    local vpn_ifaces
    vpn_ifaces=$(ip link show 2>/dev/null | grep -c 'tun\|tap\|wg' || true)
    if (( vpn_ifaces > 0 )); then
      status_info "VPN: ${vpn_ifaces} tunnel interface(s) active"
    fi
  fi

  # Proxy configuration — one scutil --proxy snapshot covers both flags
  # (issue #98: two per-service networksetup calls became one probe that
  # also sees proxies on non-Wi-Fi services). Values map 1→Yes, 0→No to
  # keep the status text identical.
  if is_macos; then
    local http_proxy="" https_proxy=""
    local proxy_info pline pkey _pcolon pval
    proxy_info=$(scutil --proxy 2>/dev/null || true)
    while IFS= read -r pline; do
      read -r pkey _pcolon pval <<< "$pline"
      case "$pkey" in
        HTTPEnable)  [ "$pval" = "1" ] && http_proxy="Yes" ;;
        HTTPSEnable) [ "$pval" = "1" ] && https_proxy="Yes" ;;
      esac
    done <<< "$proxy_info"
    if [ "$http_proxy" = "Yes" ] || [ "$https_proxy" = "Yes" ]; then
      status_info "Web proxy configured (HTTP: ${http_proxy:-No}, HTTPS: ${https_proxy:-No})"
    fi
  else
    if [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
      status_info "Proxy configured via environment variables"
    fi
  fi

  # Network interface error/drop counters
  if [ -n "$active_service" ]; then
    if is_macos; then
      # One netstat snapshot; row 2 carries the counters, fields 6 and 8
      # are the same two columns the twin invocations used to extract.
      local net_errors=0 net_drops=0
      local netstat_out net_row=""
      netstat_out=$(netstat -I "$active_service" -b 2>/dev/null || true)
      {
        IFS= read -r _net_hdr || true   # header row
        IFS= read -r net_row || true    # first data row (awk NR==2)
      } <<< "$netstat_out"
      if [ -n "$net_row" ]; then
        read -r _n1 _n2 _n3 _n4 _n5 net_errors _n7 net_drops _nrest <<< "$net_row"
        net_errors="${net_errors:-0}"
        net_drops="${net_drops:-0}"
      fi
      if [ -n "$net_errors" ] && (( net_errors > 0 )); then
        status_info "Network errors on ${active_service}: ${net_errors}"
      fi
      if [ -n "$net_drops" ] && (( net_drops > 0 )); then
        status_info "Network drops on ${active_service}: ${net_drops}"
      fi
    else
      # Linux: /sys/class/net statistics
      local rx_errors tx_errors
      rx_errors=$(cat "/sys/class/net/${active_service}/statistics/rx_errors" 2>/dev/null || true)
      tx_errors=$(cat "/sys/class/net/${active_service}/statistics/tx_errors" 2>/dev/null || true)
      local total_errors=$((${rx_errors:-0} + ${tx_errors:-0}))
      if (( total_errors > 0 )); then
        status_info "Network errors on ${active_service}: ${total_errors} (rx:${rx_errors} tx:${tx_errors})"
      fi
    fi
  fi
}
