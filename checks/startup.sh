#!/usr/bin/env bash
#
# checks/startup.sh
# Startup items & launch agents audit (read-only, SAFE)
# Category: System
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
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

        # ${f##*/} + case replace the per-plist basename subshell and
        # echo|grep prefix test (issue #98 — was 4 forks per plist).
        local plist_name
        plist_name="${f##*/}"
        case "$plist_name" in
          com.apple.*)
            ;;
          *)
            non_apple=$((non_apple + 1))
            non_apple_agents=$((non_apple_agents + 1))
            if [ -n "$non_apple_list" ]; then
              non_apple_list="${non_apple_list}, ${plist_name%.plist}"
            else
              non_apple_list="${plist_name%.plist}"
            fi
            ;;
        esac
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

    # Login items (via osascript — an AppleEvent IPC call that can hang;
    # timeout-capped with a distinct "timed out" report, issue #101)
    local login_items _li_rc=0
    tcap "$MDOCTOR_CMD_TIMEOUT_S" "Login-items probe" osascript -e 'tell application "System Events" to get the name of every login item' || _li_rc=$?
    login_items="$_TCAP_OUT"
    if [ "$_li_rc" -ne 124 ]; then
      if [ -n "$login_items" ] && [ "$login_items" != "" ]; then
        status_info "Login items: ${login_items}"
      else
        status_info "No legacy login items detected."
      fi
    fi
  else
    # Linux: systemd services
    if command -v systemctl >/dev/null 2>&1; then
      # In-shell line counts replace three wc -l|tr -d ' ' pipelines
      # (issue #98).
      local enabled_count=0 _sc_out _scl _sc_rc=0
      # systemctl calls are dbus IPC — timeout-capped with a distinct
      # "timed out" report (issue #101); a capped-out probe never prints
      # a bogus "0 services" line.
      tcap "$MDOCTOR_CMD_TIMEOUT_S" "Enabled-services probe" systemctl list-unit-files --state=enabled --type=service --no-pager --no-legend || _sc_rc=$?
      _sc_out="$_TCAP_OUT"
      if [ "$_sc_rc" -ne 124 ]; then
        while IFS= read -r _scl; do
          [ -n "$_scl" ] && enabled_count=$((enabled_count + 1))
        done <<< "$_sc_out"
        status_info "Enabled systemd services: ${enabled_count}"
      fi

      # Failed services
      local failed_count=0
      _sc_rc=0
      tcap "$MDOCTOR_CMD_TIMEOUT_S" "Failed-services probe" systemctl --failed --no-pager --no-legend || _sc_rc=$?
      _sc_out="$_TCAP_OUT"
      if [ "$_sc_rc" -ne 124 ]; then
        while IFS= read -r _scl; do
          [ -n "$_scl" ] && failed_count=$((failed_count + 1))
        done <<< "$_sc_out"
        if (( failed_count > 0 )); then
          status_warn "Failed systemd services: ${failed_count}"
          add_action "Run 'systemctl --failed' to see failed services and fix or disable them."
        else
          status_ok "No failed systemd services."
        fi
      fi

      # User services
      local user_enabled=0
      _sc_rc=0
      tcap "$MDOCTOR_CMD_TIMEOUT_S" "User-services probe" systemctl --user list-unit-files --state=enabled --type=service --no-pager --no-legend || _sc_rc=$?
      _sc_out="$_TCAP_OUT"
      if [ "$_sc_rc" -ne 124 ]; then
        while IFS= read -r _scl; do
          [ -n "$_scl" ] && user_enabled=$((user_enabled + 1))
        done <<< "$_sc_out"
        if (( user_enabled > 0 )); then
          status_info "User-level enabled services: ${user_enabled}"
        fi
      fi
    else
      status_info "systemd not available; startup check skipped."
    fi
  fi
}
