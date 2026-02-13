#!/usr/bin/env bash
#
# checks/security.sh
# Security & privacy audit (read-only, SAFE)
# Category: System
#

check_security() {
  step "Security & Privacy"

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

  # Processes listening on network ports (count)
  local listening_count
  listening_count=$(lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  if [ -n "$listening_count" ] && (( listening_count > 0 )); then
    status_info "Processes listening on TCP ports: ${listening_count}"
  fi

  # Automatic login
  local auto_login
  auto_login=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || echo "")
  if [ -n "$auto_login" ]; then
    status_warn "Automatic login enabled for user: ${auto_login}"
    add_action "Disable automatic login: System Settings > Users & Groups > Automatic login"
  fi
}
