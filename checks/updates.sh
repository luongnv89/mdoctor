#!/usr/bin/env bash
#
# checks/updates.sh
# macOS update status checks
#

check_updates_basic() {
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
    add_action "Ensure macOS softwareupdate tools are available (usually present by default; if missing, investigate OS installation)."
  fi
}
