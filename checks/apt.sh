#!/usr/bin/env bash
#
# checks/apt.sh
# APT package manager health (read-only, SAFE)
# Category: Software
# Platform: Linux (Debian-family) only
#

check_apt() {
  step "APT Package Manager"

  if ! command -v apt-get >/dev/null 2>&1; then
    status_info "APT not available on this system."
    return 0
  fi

  # Package count
  if command -v dpkg >/dev/null 2>&1; then
    local installed_count installed_count_raw
    installed_count_raw=$(dpkg -l 2>/dev/null | grep -c '^ii' || true)
    installed_count=$(to_int "$installed_count_raw")
    status_info "Installed packages: ${installed_count}"
  fi

  # Held-back packages
  local held_count
  held_count=$(apt-mark showhold 2>/dev/null | wc -l | tr -d ' ')
  if (( held_count > 0 )); then
    status_info "Held-back packages: ${held_count}"
  fi

  # Broken packages
  local broken_output
  broken_output=$(dpkg --audit 2>/dev/null || true)
  if [ -n "$broken_output" ]; then
    status_warn "Broken packages detected"
    add_action "Fix broken packages: sudo dpkg --configure -a && sudo apt --fix-broken install"
  else
    status_ok "No broken packages."
  fi

  # Residual configs (packages removed but config files remain)
  local residual_count residual_count_raw
  residual_count_raw=$(dpkg -l 2>/dev/null | grep -c '^rc' || true)
  residual_count=$(to_int "$residual_count_raw")
  if (( residual_count > 5 )); then
    status_info "Packages with residual configs: ${residual_count}"
    add_action "Clean residual configs: sudo apt purge \$(dpkg -l | grep '^rc' | awk '{print \$2}')"
  fi

  # APT cache size
  local cache_size cache_size_raw
  cache_size_raw=$(du -sk /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || true)
  cache_size=$(to_int "$cache_size_raw")
  if (( cache_size > 524288 )); then  # > 512 MB
    local cache_hr
    cache_hr=$(kb_to_human "$cache_size")
    status_info "APT cache size: ${cache_hr}"
    add_action "Clean APT cache: sudo apt clean"
  fi

  # Auto-removable packages
  local autoremove_output autoremove_output_raw
  autoremove_output_raw=$(apt-get -s autoremove 2>/dev/null | grep -c '^Remv' || true)
  autoremove_output=$(to_int "$autoremove_output_raw")
  if (( autoremove_output > 0 )); then
    status_info "Auto-removable packages: ${autoremove_output}"
    add_action "Remove unused packages: sudo apt autoremove"
  fi
}
