#!/usr/bin/env bash
#
# checks/network.sh
# Network connectivity checks
#

check_network() {
  step "Network connectivity (basic)"

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
}
