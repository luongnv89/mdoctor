#!/usr/bin/env bash
#
# checks/network.sh
# Network connectivity & diagnostics (read-only, SAFE)
# Category: System
#

check_network() {
  step "Network Diagnostics"

  # Basic connectivity
  if ping -c 1 -W 1000 1.1.1.1 >/dev/null 2>&1; then
    status_ok "Can reach the internet (ping 1.1.1.1 succeeded)."
  else
    status_warn "Ping to 1.1.1.1 failed."
    add_action "Check network connectivity or firewall rules (ping to 1.1.1.1 fails)."
  fi

  if ping -c 1 -W 1000 github.com >/dev/null 2>&1; then
    status_ok "Can reach github.com."
  else
    status_warn "Cannot reach github.com."
    add_action "Check DNS / network configuration: unable to reach github.com."
  fi

  # DNS resolution speed
  local dns_start dns_end dns_ms
  dns_start=$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time()' 2>/dev/null || echo "")
  if [ -n "$dns_start" ]; then
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

  # Active network service
  local active_service
  if is_macos; then
    active_service=$(route get default 2>/dev/null | awk '/interface:/ {print $2}')
  else
    active_service=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
  fi
  if [ -n "$active_service" ]; then
    status_info "Active network interface: ${active_service}"

    # Local IP address on the active interface
    local local_ip
    if is_macos; then
      local_ip=$(ipconfig getifaddr "$active_service" 2>/dev/null || echo "")
    else
      local_ip=$(ip -4 addr show "$active_service" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
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
      if [ -n "$wifi_info" ] && ! echo "$wifi_info" | grep -q "AirPort: Off"; then
        local rssi noise ssid
        rssi=$(echo "$wifi_info" | awk '/agrCtlRSSI/ {print $2}')
        noise=$(echo "$wifi_info" | awk '/agrCtlNoise/ {print $2}')
        ssid=$(echo "$wifi_info" | awk -F': ' '/[[:space:]]SSID:/ {print $2}')

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
      if [ -n "$wifi_info" ] && ! echo "$wifi_info" | grep -q "Not connected"; then
        local ssid signal
        ssid=$(echo "$wifi_info" | awk -F': ' '/SSID:/ {print $2}')
        signal=$(echo "$wifi_info" | awk '/signal:/ {print $2}')
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

  # Proxy configuration
  if is_macos; then
    local http_proxy https_proxy
    http_proxy=$(networksetup -getwebproxy Wi-Fi 2>/dev/null | awk '/Enabled:/ {print $2; exit}' || true)
    https_proxy=$(networksetup -getsecurewebproxy Wi-Fi 2>/dev/null | awk '/Enabled:/ {print $2; exit}' || true)
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
      local net_errors net_drops
      net_errors=$(netstat -I "$active_service" -b 2>/dev/null | awk 'NR==2 {print $6}' || echo "0")
      net_drops=$(netstat -I "$active_service" -b 2>/dev/null | awk 'NR==2 {print $8}' || echo "0")
      if [ -n "$net_errors" ] && (( net_errors > 0 )); then
        status_info "Network errors on ${active_service}: ${net_errors}"
      fi
      if [ -n "$net_drops" ] && (( net_drops > 0 )); then
        status_info "Network drops on ${active_service}: ${net_drops}"
      fi
    else
      # Linux: /sys/class/net statistics
      local rx_errors tx_errors
      rx_errors=$(cat "/sys/class/net/${active_service}/statistics/rx_errors" 2>/dev/null || echo 0)
      tx_errors=$(cat "/sys/class/net/${active_service}/statistics/tx_errors" 2>/dev/null || echo 0)
      local total_errors=$((rx_errors + tx_errors))
      if (( total_errors > 0 )); then
        status_info "Network errors on ${active_service}: ${total_errors} (rx:${rx_errors} tx:${tx_errors})"
      fi
    fi
  fi
}
