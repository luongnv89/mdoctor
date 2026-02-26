#!/usr/bin/env bash
#
# checks/security.sh
# Security & privacy audit (read-only, SAFE)
# Category: System
#

check_security() {
  step "Security & Privacy"

  if is_macos; then
    # Firewall status
    local fw_status
    fw_status=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
    if echo "$fw_status" | grep -qi "enabled"; then
      status_ok "Firewall: enabled"
    elif echo "$fw_status" | grep -qi "disabled"; then
      status_warn "Firewall: disabled"
      add_action "Enable the macOS firewall: System Settings > Network > Firewall"
    else
      status_info "Firewall status: could not determine"
    fi

    # FileVault / disk encryption
    local fv_status
    fv_status=$(fdesetup status 2>/dev/null || true)
    if echo "$fv_status" | grep -qi "On"; then
      status_ok "FileVault: enabled"
    elif echo "$fv_status" | grep -qi "Off"; then
      status_warn "FileVault: disabled (disk not encrypted)"
      add_action "Enable FileVault for disk encryption: System Settings > Privacy & Security > FileVault"
    else
      status_info "FileVault status: could not determine"
    fi

    # System Integrity Protection
    local sip_status
    sip_status=$(csrutil status 2>/dev/null || true)
    if echo "$sip_status" | grep -qi "enabled"; then
      status_ok "System Integrity Protection (SIP): enabled"
    elif echo "$sip_status" | grep -qi "disabled"; then
      status_fail "System Integrity Protection (SIP): disabled"
      add_action "SIP is disabled. This is a security risk. Re-enable via Recovery Mode: csrutil enable"
    else
      status_info "SIP status: could not determine"
    fi

    # Gatekeeper
    local gk_status
    gk_status=$(spctl --status 2>/dev/null || true)
    if echo "$gk_status" | grep -qi "enabled"; then
      status_ok "Gatekeeper: enabled"
    elif echo "$gk_status" | grep -qi "disabled"; then
      status_warn "Gatekeeper: disabled"
      add_action "Enable Gatekeeper: sudo spctl --master-enable"
    else
      status_info "Gatekeeper status: could not determine"
    fi

    # Remote Login (SSH)
    local remote_login
    remote_login=$(systemsetup -getremotelogin 2>/dev/null || true)
    if echo "$remote_login" | grep -qi "On"; then
      status_info "Remote Login (SSH): enabled"
    elif echo "$remote_login" | grep -qi "Off"; then
      status_ok "Remote Login (SSH): disabled"
    fi

    # Screen Sharing
    local screen_sharing
    screen_sharing=$(launchctl list 2>/dev/null | grep -c "com.apple.screensharing" || true)
    if (( screen_sharing > 0 )); then
      status_info "Screen Sharing: active"
    fi

    # Remote Management
    local remote_mgmt
    remote_mgmt=$(launchctl list 2>/dev/null | grep -c "com.apple.RemoteDesktop" || true)
    if (( remote_mgmt > 0 )); then
      status_info "Remote Management: active"
    fi

    # Automatic login
    local auto_login
    auto_login=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || echo "")
    if [ -n "$auto_login" ]; then
      status_warn "Automatic login enabled for user: ${auto_login}"
      add_action "Disable automatic login: System Settings > Users & Groups > Automatic login"
    fi
  else
    # Linux: firewall, disk encryption, SSH, unattended upgrades

    # Firewall (ufw or iptables)
    if command -v ufw >/dev/null 2>&1; then
      local ufw_status
      ufw_status=$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo "")
      if echo "$ufw_status" | grep -qi "active"; then
        status_ok "Firewall (ufw): active"
      elif echo "$ufw_status" | grep -qi "inactive"; then
        status_warn "Firewall (ufw): inactive"
        add_action "Enable the firewall: sudo ufw enable"
      else
        status_info "Firewall (ufw): could not determine status"
      fi
    elif command -v iptables >/dev/null 2>&1; then
      local ipt_rules ipt_rules_raw
      ipt_rules_raw=$(sudo iptables -L -n 2>/dev/null | grep -cv '^$\|^Chain\|^target' || true)
      ipt_rules=$(to_int "$ipt_rules_raw")
      if (( ipt_rules > 0 )); then
        status_ok "Firewall (iptables): ${ipt_rules} rules active"
      else
        status_warn "Firewall (iptables): no rules configured"
        add_action "Consider configuring firewall rules with iptables or installing ufw."
      fi
    else
      status_info "No firewall tool found (ufw/iptables)"
    fi

    # Disk encryption (LUKS)
    if command -v lsblk >/dev/null 2>&1; then
      local crypt_count crypt_count_raw
      crypt_count_raw=$(lsblk -o TYPE 2>/dev/null | grep -c "crypt" || true)
      crypt_count=$(to_int "$crypt_count_raw")
      if (( crypt_count > 0 )); then
        status_ok "Disk encryption (LUKS): ${crypt_count} encrypted volume(s)"
      else
        status_info "Disk encryption: no LUKS volumes detected"
      fi
    fi

    # SSH server
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
        status_info "SSH server: running"
      else
        status_ok "SSH server: not running"
      fi
    fi

    # Unattended upgrades
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
      status_ok "Unattended upgrades: installed"
    else
      status_info "Unattended upgrades: not installed"
      add_action "Consider installing unattended-upgrades for automatic security updates."
    fi
  fi

  # Cross-platform: processes listening on TCP ports
  local listening_count
  if is_macos; then
    listening_count=$(lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  else
    listening_count=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  fi
  if [ -n "$listening_count" ] && (( listening_count > 0 )); then
    status_info "Processes listening on TCP ports: ${listening_count}"
  fi
}
