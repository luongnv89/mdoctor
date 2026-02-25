#!/usr/bin/env bash
#
# checks/startup.sh
# Startup items & launch agents audit (read-only, SAFE)
# Category: System
#

check_startup() {
  step "Startup Items & Services"

  if is_macos; then
    local total_agents=0
    local non_apple_agents=0
    local non_apple_list=""

    # Scan launch directories
    local dir
    for dir in \
      /Library/LaunchDaemons \
      /Library/LaunchAgents \
      "${HOME}/Library/LaunchAgents"; do

      if [ ! -d "$dir" ]; then
        continue
      fi

      local count=0
      local non_apple=0
      local f

      for f in "$dir"/*.plist; do
        [ -f "$f" ] || continue
        count=$((count + 1))
        total_agents=$((total_agents + 1))

        local basename
        basename="$(basename "$f")"
        if ! echo "$basename" | grep -q '^com\.apple\.'; then
          non_apple=$((non_apple + 1))
          non_apple_agents=$((non_apple_agents + 1))
          if [ -n "$non_apple_list" ]; then
            non_apple_list="${non_apple_list}, ${basename%.plist}"
          else
            non_apple_list="${basename%.plist}"
          fi
        fi
      done

      local dir_label
      dir_label="${dir/${HOME}/~}"
      status_info "${dir_label}: ${count} items (${non_apple} non-Apple)"
    done

    if (( non_apple_agents > 15 )); then
      status_warn "High number of non-Apple startup items: ${non_apple_agents} (total: ${total_agents})"
      add_action "Review startup items. ${non_apple_agents} non-Apple agents/daemons found. Consider disabling unused ones."
    elif (( non_apple_agents > 0 )); then
      status_ok "Non-Apple startup items: ${non_apple_agents} (total: ${total_agents})"
    else
      status_ok "Only Apple startup items found (${total_agents} total)."
    fi

    # Login items (via osascript)
    local login_items
    login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
    if [ -n "$login_items" ] && [ "$login_items" != "" ]; then
      status_info "Login items: ${login_items}"
    else
      status_info "No legacy login items detected."
    fi
  else
    # Linux: systemd services
    if command -v systemctl >/dev/null 2>&1; then
      local enabled_count
      enabled_count=$(systemctl list-unit-files --state=enabled --type=service --no-pager --no-legend 2>/dev/null | wc -l | tr -d ' ')
      status_info "Enabled systemd services: ${enabled_count}"

      # Failed services
      local failed_count
      failed_count=$(systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l | tr -d ' ')
      if (( failed_count > 0 )); then
        status_warn "Failed systemd services: ${failed_count}"
        add_action "Run 'systemctl --failed' to see failed services and fix or disable them."
      else
        status_ok "No failed systemd services."
      fi

      # User services
      local user_enabled
      user_enabled=$(systemctl --user list-unit-files --state=enabled --type=service --no-pager --no-legend 2>/dev/null | wc -l | tr -d ' ')
      if (( user_enabled > 0 )); then
        status_info "User-level enabled services: ${user_enabled}"
      fi
    fi
  fi
}
