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

  # DNS resolution speed — the lookup is timeout-capped (issue #101): a
  # wedged resolver used to hang this module until the DNS probe gave up.
  local dns_start dns_end dns_ms
  dns_start=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()' 2>/dev/null || echo "")
  if ! command -v nslookup >/dev/null 2>&1; then   # presence probe — the lookup below is timeout-capped
    status_info "Skipping DNS timing probe: nslookup not found."   # timeout-capped when present
  elif [ -n "$dns_start" ]; then
    local _ns_rc=0
    mdoctor_timeout "$MDOCTOR_DNS_TIMEOUT_S" nslookup google.com >/dev/null 2>&1 || _ns_rc=$?
    dns_end=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()' 2>/dev/null || echo "")
    if [ "$_ns_rc" -eq 124 ]; then
      status_warn "DNS resolution timed out (timeout ${MDOCTOR_DNS_TIMEOUT_S}s)"
      add_action "DNS resolution timed out — check resolver and network configuration."
    elif [ -n "$dns_end" ]; then
      dns_ms=$(awk -v s="$dns_start" -v e="$dns_end" 'BEGIN {printf "%.0f", (e-s)*1000}')
      if is_uint "$dns_ms"; then
        if (( 10#$dns_ms > 500 )); then
          status_warn "DNS resolution: ${dns_ms}ms (slow, >500ms)"
          add_action "DNS resolution is slow (${dns_ms}ms). Consider switching to faster DNS (1.1.1.1 or 8.8.8.8)."
        else
          status_ok "DNS resolution: ${dns_ms}ms"
        fi
      else
        status_info "DNS resolution: could not determine"
      fi
    fi
  fi

  # Active network service — in-shell field splits replace the
  # route/ip|awk extractions (issue #98).
  local active_service=""
  if is_macos; then
    local _rt_out _rtl _rk _rv
    tcap "$MDOCTOR_NET_TIMEOUT_S" "Default-route probe" route get default || true
    _rt_out="$_TCAP_OUT"
    while IFS= read -r _rtl; do
      read -r _rk _rv _ <<< "$_rtl"
      if [ "$_rk" = "interface:" ]; then
        active_service="$_rv"
      fi
    done <<< "$_rt_out"
  else
    local _ipr _i1 _i2 _i3 _i4
    tcap "$MDOCTOR_NET_TIMEOUT_S" "Default-route probe" ip route show default || true
    _ipr="$_TCAP_OUT"
    # First row only — the retired awk '{print $5; exit}'.
    read -r _i1 _i2 _i3 _i4 active_service _ <<< "$_ipr"
  fi
  if [ -n "$active_service" ]; then
    status_info "Active network interface: ${active_service}"

    # Local IP address on the active interface
    local local_ip=""
    if is_macos; then
      tcap "$MDOCTOR_NET_TIMEOUT_S" "Interface-address probe" ipconfig getifaddr "$active_service" || true
      local_ip="$_TCAP_OUT"
    else
      local _ia_out _ial _iaf1 _iaf2
      tcap "$MDOCTOR_NET_TIMEOUT_S" "Interface-address probe" ip -4 addr show "$active_service" || true
      _ia_out="$_TCAP_OUT"
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
      tcap "$MDOCTOR_NET_TIMEOUT_S" "AirPort info probe" "$airport_path" -I || true
      wifi_info="$_TCAP_OUT"
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
          # Signed-integer gate (issue #111): non-numeric dBm fields used
          # to coerce to 0 and read as a poor-signal warning.
          if ! is_uint "${rssi#-}" || ! is_uint "${noise#-}"; then
            status_info "Wi-Fi signal: could not determine"
          else
            # Base-10 normalize before arithmetic (issue #111): 10#
            # cannot take a sign, and a bare "-08" would hit bash's
            # octal parser (error token) while "-042" would silently
            # misparse — strip the sign, 10# the magnitude, reapply.
            local _rs=$((10#${rssi#-})) _ns=$((10#${noise#-}))
            case "$rssi"  in -*) _rs=$((-_rs)) ;; esac
            case "$noise" in -*) _ns=$((-_ns)) ;; esac
            local snr=$((_rs - _ns))
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
    fi
  else
    # Linux: Wi-Fi via iw or iwconfig
    if command -v iw >/dev/null 2>&1 && [ -n "$active_service" ]; then
      local wifi_info
      tcap "$MDOCTOR_NET_TIMEOUT_S" "iw link probe" iw dev "$active_service" link || true
      wifi_info="$_TCAP_OUT"
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
          # Same signed-integer gate (issue #111).
          if ! is_uint "${sig_val#-}"; then
            status_info "Wi-Fi signal: could not determine"
          else
            # Same base-10 normalization: the sign is stripped for the
            # gate, so it must be reapplied after 10# (a raw "-08" is an
            # octal error token, "-042" a silent misparse).
            local _sv=$((10#${sig_val#-}))
            case "$sig_val" in -*) _sv=$((-_sv)) ;; esac
            if (( _sv < -75 )); then
              status_warn "Wi-Fi signal: ${signal} dBm (weak)"
            else
              status_ok "Wi-Fi signal: ${signal} dBm"
            fi
          fi
        fi
      fi
    fi
  fi

  # VPN connection status (scutil talks to configd — capped, issue #101)
  if is_macos; then
    local vpn_active _vpn_rc=0
    tcap "$MDOCTOR_NET_TIMEOUT_S" "VPN status probe" scutil --nc list || _vpn_rc=$?
    if [ "$_vpn_rc" -ne 124 ]; then
      vpn_active=$(printf '%s\n' "$_TCAP_OUT" | grep -c "Connected" || true)
      if (( vpn_active > 0 )); then
        status_info "VPN: ${vpn_active} connection(s) active"
      fi
    fi
  else
    # Linux: check for tun/tap interfaces or active VPN connections
    local vpn_ifaces
    tcap "$MDOCTOR_NET_TIMEOUT_S" "VPN interface probe" ip link show || true
    vpn_ifaces=$(printf '%s\n' "$_TCAP_OUT" | grep -c 'tun\|tap\|wg' || true)
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
    tcap "$MDOCTOR_NET_TIMEOUT_S" "Proxy configuration probe" scutil --proxy || true
    proxy_info="$_TCAP_OUT"
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
      # One netstat snapshot (issue #111): the counters row is matched by
      # interface name — never a fixed NR==2 position — and the Ierrs /
      # Oerrs column indexes come from the header row, so a column-order
      # change can never land Opkts in "Network drops" again.
      local net_errors="" net_drops=""
      local netstat_out _net_hdr=""
      tcap "$MDOCTOR_NET_TIMEOUT_S" "Interface-counters probe" netstat -I "$active_service" -b || true
      netstat_out="$_TCAP_OUT"
      local _nname_i=0 _nierrs_i=0 _noerrs_i=0 _nh=0 _hf
      IFS= read -r _net_hdr <<< "$netstat_out" || true
      for _hf in $_net_hdr; do
        _nh=$((_nh + 1))
        case "$_hf" in
          Name)  _nname_i="$_nh" ;;
          Ierrs) _nierrs_i="$_nh" ;;
          Oerrs) _noerrs_i="$_nh" ;;
        esac
      done
      if [ "$_nname_i" -gt 0 ] && [ "$_nierrs_i" -gt 0 ] && [ "$_noerrs_i" -gt 0 ]; then
        local _nrow _nf _nv
        while IFS= read -r _nrow; do
          _nf=0
          local _rname="" _rierrs="" _roerrs=""
          for _nv in $_nrow; do
            _nf=$((_nf + 1))
            [ "$_nf" -eq "$_nname_i" ]  && _rname="$_nv"
            [ "$_nf" -eq "$_nierrs_i" ] && _rierrs="$_nv"
            [ "$_nf" -eq "$_noerrs_i" ] && _roerrs="$_nv"
          done
          if [ "$_rname" = "$active_service" ]; then
            net_errors="$_rierrs"
            net_drops="$_roerrs"
            break
          fi
        done <<< "$netstat_out"
      fi
      if is_uint "$net_errors" && is_uint "$net_drops"; then
        if (( 10#$net_errors > 0 )); then
          status_info "Network errors on ${active_service}: ${net_errors}"
        fi
        if (( 10#$net_drops > 0 )); then
          status_info "Network drops on ${active_service}: ${net_drops}"
        fi
      elif [ -n "$netstat_out" ]; then
        # netstat answered but no matching row or unreadable columns —
        # report the failure honestly, never a coerced 0 (issue #111).
        status_info "Network counters on ${active_service}: could not determine"
      fi
    else
      # Linux: /sys/class/net statistics
      local rx_errors tx_errors
      rx_errors=$(cat "/sys/class/net/${active_service}/statistics/rx_errors" 2>/dev/null || true)
      tx_errors=$(cat "/sys/class/net/${active_service}/statistics/tx_errors" 2>/dev/null || true)
      if is_uint "$rx_errors" && is_uint "$tx_errors"; then
        local total_errors=$((10#$rx_errors + 10#$tx_errors))
        if (( total_errors > 0 )); then
          status_info "Network errors on ${active_service}: ${total_errors} (rx:${rx_errors} tx:${tx_errors})"
        fi
      else
        status_info "Network errors on ${active_service}: could not determine"
      fi
    fi
  fi
}
