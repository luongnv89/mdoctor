#!/usr/bin/env bash
#
# fixes/dns.sh
# Flush DNS cache
# Risk: LOW
#

fix_dns() {
  echo "${BOLD}${BLUE}== Flushing DNS Cache ==${RESET}"
  echo

  echo "Flushing macOS DNS cache..."
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true

  echo "${GREEN}DNS cache flushed.${RESET}"
}
