#!/usr/bin/env bash
#
# checks/apps.sh
# Application health & crash analysis (read-only, SAFE)
# Category: Software
#
# Note: system_profiler SPApplicationsDataType is very slow (~30s).
# 32-bit check only runs when this module is invoked directly via -m apps.
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
check_apps() {
  step "Application Health"

  # Recent crash reports (last 7 days)
  local crash_dirs=()
  if is_macos; then
    [ -d "${HOME}/Library/Logs/DiagnosticReports" ] && crash_dirs+=("${HOME}/Library/Logs/DiagnosticReports")
    [ -d "/Library/Logs/DiagnosticReports" ] && crash_dirs+=("/Library/Logs/DiagnosticReports")
  else
    [ -d "/var/crash" ] && crash_dirs+=("/var/crash")
    [ -d "${HOME}/.local/share/apport" ] && crash_dirs+=("${HOME}/.local/share/apport")
  fi

  local total_crashes=0
  local crash_apps=""
  local dir

  # Bash 3.2 floor: "${arr[@]}" on an empty array is unbound under
  # `set -u` — the ${arr[@]+"${arr[@]}"} idiom expands to nothing instead.
  for dir in "${crash_dirs[@]+"${crash_dirs[@]}"}"; do
    local crashes
    crashes=$(find "$dir" -type f \( -name "*.crash" -o -name "*.ips" -o -name "*.diag" \) -mtime -7 2>/dev/null || true)
    if [ -n "$crashes" ]; then
      local count=0 _cline
      while IFS= read -r _cline; do
        count=$((count + 1))
      done <<< "$crashes"
      total_crashes=$((total_crashes + count))

      local app_names
      # One batched sed replaces per-file xargs -I{} basename {} (issue
      # #98): s|.*/|| strips the directory, s/[-_].*// the date suffix.
      app_names=$(printf '%s\n' "$crashes" | sed 's|.*/||; s/[-_].*//' | sort | uniq -c | sort -rn | head -5)
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

  if [ -n "$crash_apps" ]; then
    status_info "Top crashing apps:"
    local cnt name _crest
    while read -r cnt name _crest; do
      if [ -n "$name" ]; then
        status_info "  ${name}: ${cnt} crashes"
      fi
    done <<< "$crash_apps"
  fi

  # Application count — in-shell line counts, no wc|tr / grep -c
  # pipelines (issue #98).
  if is_macos; then
    local app_count=0 _md_out _mdl
    _md_out=$(mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null || true)
    while IFS= read -r _mdl; do
      [ -n "$_mdl" ] && app_count=$((app_count + 1))
    done <<< "$_md_out"
    if (( app_count > 0 )); then
      status_info "Installed applications: approximately ${app_count}"
    fi
  else
    if command -v dpkg >/dev/null 2>&1; then
      local pkg_count=0 _dp _dpl
      _dp=$(dpkg -l 2>/dev/null || true)
      while IFS= read -r _dpl; do
        case "$_dpl" in
          ii*) pkg_count=$((pkg_count + 1)) ;;
        esac
      done <<< "$_dp"
      status_info "Installed packages (dpkg): ${pkg_count}"
    fi
  fi
}
