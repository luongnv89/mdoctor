#!/usr/bin/env bash
#
# checks/apps.sh
# Application health & crash analysis (read-only, SAFE)
# Category: Software
#
# Note: system_profiler SPApplicationsDataType is very slow (~30s).
# 32-bit check only runs when this module is invoked directly via -m apps.
#

check_apps() {
  step "Application Health"

  # Recent crash reports (last 7 days)
  local crash_dirs=()
  [ -d "${HOME}/Library/Logs/DiagnosticReports" ] && crash_dirs+=("${HOME}/Library/Logs/DiagnosticReports")
  [ -d "/Library/Logs/DiagnosticReports" ] && crash_dirs+=("/Library/Logs/DiagnosticReports")

  local total_crashes=0
  local crash_apps=""
  local dir

  for dir in "${crash_dirs[@]}"; do
    local crashes
    crashes=$(find "$dir" -type f \( -name "*.crash" -o -name "*.ips" -o -name "*.diag" \) -mtime -7 2>/dev/null || true)
    if [ -n "$crashes" ]; then
      local count
      count=$(echo "$crashes" | wc -l | tr -d ' ')
      total_crashes=$((total_crashes + count))

      # Parse app names from crash filenames (format: AppName_date.crash)
      local app_names
      app_names=$(echo "$crashes" | xargs -I{} basename {} 2>/dev/null | sed 's/[-_].*//' | sort | uniq -c | sort -rn | head -5)
      if [ -n "$app_names" ]; then
        crash_apps="${crash_apps}${app_names}"
      fi
    fi
  done

  if (( total_crashes > 10 )); then
    status_warn "Recent crash reports (7 days): ${total_crashes}"
    add_action "Found ${total_crashes} crash reports in the last 7 days. Run 'mdoctor clean -m crash_reports' to clean old ones."
  elif (( total_crashes > 0 )); then
    status_info "Recent crash reports (7 days): ${total_crashes}"
  else
    status_ok "No crash reports in the last 7 days."
  fi

  # Top crashing apps
  if [ -n "$crash_apps" ]; then
    status_info "Top crashing apps:"
    local line
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      if [ -n "$line" ]; then
        local cnt name
        cnt=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        status_info "  ${name}: ${cnt} crashes"
      fi
    done <<< "$crash_apps"
  fi

  # Application count (fast method using mdfind)
  local app_count
  app_count=$(mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$app_count" ] && (( app_count > 0 )); then
    status_info "Installed applications: approximately ${app_count}"
  fi
}
