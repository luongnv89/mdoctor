#!/usr/bin/env bash
#
# fixes/dns.sh
# Flush DNS cache
# Risk: LOW
#

fix_dns() {
  echo "${BOLD}${BLUE}== Flushing DNS Cache ==${RESET}"
  echo

  if is_macos; then
    echo "Flushing macOS DNS cache..."
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
  else
    echo "Flushing Linux DNS cache..."
    if command -v resolvectl >/dev/null 2>&1; then
      sudo resolvectl flush-caches 2>/dev/null || true
    elif command -v systemd-resolve >/dev/null 2>&1; then
      sudo systemd-resolve --flush-caches 2>/dev/null || true
    else
      echo "No systemd-resolved found. If using nscd: sudo systemctl restart nscd"
    fi
  fi

  echo "${GREEN}DNS cache flushed.${RESET}"
}
