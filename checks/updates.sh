#!/usr/bin/env bash
#
# checks/updates.sh
# System update status checks
#

check_updates_basic() {
  if is_macos; then
    step "Basic update status (Spotlight & softwareupdate)"

    # Spotlight indexing
    if command -v mdutil >/dev/null 2>&1; then
      local md
      md=$(mdutil -s / 2>/dev/null || true)
      status_info "Spotlight: ${md}"
    fi

    # softwareupdate quick check
    if command -v softwareupdate >/dev/null 2>&1; then
      if softwareupdate -l 2>/dev/null | grep -qi "No new software available"; then
        status_ok "No macOS software updates reported."
      else
        status_warn "There may be macOS updates available."
        add_action "Run 'softwareupdate -l' and apply pending macOS updates via System Settings."
      fi
    else
      status_warn "softwareupdate command not available."
      add_action "Ensure macOS softwareupdate tools are available."
    fi
  else
    step "System Updates"

    # APT package updates
    if command -v apt-get >/dev/null 2>&1; then
      local upgradable
      upgradable=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || echo 0)
      if (( upgradable > 0 )); then
        status_warn "${upgradable} package update(s) available"
        add_action "Run 'sudo apt update && sudo apt upgrade' to apply pending updates."
      else
        status_ok "All packages are up to date."
      fi

      # Security updates specifically
      if command -v apt-get >/dev/null 2>&1; then
        local security_updates
        security_updates=$(apt-get -s upgrade 2>/dev/null | grep -c 'Inst.*security' || echo 0)
        if (( security_updates > 0 )); then
          status_warn "${security_updates} security update(s) pending"
          add_action "Security updates are pending. Run 'sudo apt upgrade' promptly."
        fi
      fi
    fi

    # Kernel update check
    local running_kernel installed_kernel
    running_kernel=$(uname -r 2>/dev/null || echo "")
    if [ -n "$running_kernel" ]; then
      status_info "Running kernel: ${running_kernel}"
    fi
  fi
}
