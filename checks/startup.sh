#!/usr/bin/env bash
#
# checks/startup.sh
# Startup items & launch agents audit (read-only, SAFE)
# Category: System
#

check_startup() {
  step "Startup Items & Launch Agents"

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
      # Non-Apple: doesn't start with com.apple.
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

  # Summary
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
}
