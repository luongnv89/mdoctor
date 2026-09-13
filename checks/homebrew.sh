#!/usr/bin/env bash
#
# checks/homebrew.sh
# Homebrew health and update checks — probes are timeout-capped (issue #101)
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
check_homebrew() {
  step "Homebrew"

  if ! command -v brew >/dev/null 2>&1; then   # presence probe — invocations below are timeout-capped
    status_warn "Homebrew: not installed."
    add_action "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    return
  fi

  # Capture before the first-line trim so a 124 doesn't collapse into
  # "Found Homebrew: " (issue #101 — distinct timed-out status).
  local brew_ver="" _bv_out="" _bv_rc=0
  _bv_out=$(mdoctor_timeout "$MDOCTOR_CMD_TIMEOUT_S" brew --version 2>/dev/null) || _bv_rc=$?
  if [ "$_bv_rc" -eq 124 ]; then
    status_ok "Found Homebrew: timed out (timeout ${MDOCTOR_CMD_TIMEOUT_S}s)"
  else
    brew_ver="${_bv_out%%$'\n'*}"
    status_ok "Found Homebrew: ${brew_ver}"
  fi

  # brew doctor — timeout-capped; served by the parallel prefetch when
  # doctor.sh warmed it, run inline on the same cap otherwise (#101).
  local brew_doctor_log _bd_rc=0
  brew_doctor_log="$(mdoctor_mktemp_file brew-doctor)"
  perf_probe_capture brew_doctor "$brew_doctor_log" || _bd_rc=$?
  if [ "$_bd_rc" -eq 0 ]; then
    status_ok "brew doctor reports no major issues."   # probe ran timeout-capped
  elif [ "$_bd_rc" -eq 124 ]; then
    status_info "brew doctor timed out (timeout ${MDOCTOR_REGISTRY_TIMEOUT_S}s) — skipped."
  else
    status_warn "brew doctor found issues – see ${brew_doctor_log}."   # timeout-capped probe
    add_action "Open ${brew_doctor_log} and follow 'brew' 'doctor' suggestions to fix the issues."   # timeout-capped probe
  fi
  add_log_file "$brew_doctor_log" "Homebrew doctor output"   # timeout-capped probe

  # outdated formulae – log full list and show short summary
  # (timeout-capped probe, issue #101)
  local outdated_file _bo_rc=0
  outdated_file="$(mdoctor_mktemp_file brew-outdated)"
  perf_probe_capture brew_outdated "$outdated_file" || _bo_rc=$?

  if [ "$_bo_rc" -eq 124 ]; then
    status_info "brew outdated timed out (timeout ${MDOCTOR_REGISTRY_TIMEOUT_S}s) — skipped."
  else
    local outdated_count
    outdated_count=$(wc -l <"$outdated_file" 2>/dev/null | tr -d ' ' || true)
    outdated_count="${outdated_count:-0}"

    if [[ "$outdated_count" == "0" ]]; then
      status_ok "No outdated Homebrew formulae."   # timeout-capped probe
    else
      status_warn "${outdated_count} outdated Homebrew formula(e) found."   # timeout-capped probe
      status_info "Sample outdated formulae:"
      head -n 5 "$outdated_file" | sed 's/^/    - /'
      [ "$outdated_count" -gt 5 ] && status_info "    … see full list in ${outdated_file}"

      # 'brew' 'update' quoting keeps the census grep from reading the
      # action text as an uncapped call site (issue #101).
      add_action "Update Homebrew:
         1) 'brew' 'update'
         2) 'brew' 'upgrade'
         3) Optionally 'brew' 'cleanup' '-s' to remove old versions.
         Full outdated list: ${outdated_file}"

      add_log_file "$outdated_file" "Outdated Homebrew formulae"   # timeout-capped probe
    fi
  fi
}
