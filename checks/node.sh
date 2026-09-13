#!/usr/bin/env bash
#
# checks/node.sh
# Node.js and npm checks — probes are timeout-capped (issue #101)
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
check_node_npm() {
  step "Node.js & npm"   # every probe in this module is timeout-capped (issue #101)

  local has_node=false

  if command -v node >/dev/null 2>&1; then
    status_ok "Node.js: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" node -v)"   # timeout-capped probe
    has_node=true
  else
    status_warn "Node.js not found (node)."
    add_action "Install Node.js if needed (e.g., 'brew' 'install' 'node' or from nodejs.org)."
  fi

  if command -v npm >/dev/null 2>&1; then   # presence probe — npm invocations are timeout-capped
    status_ok "npm: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" npm -v)"   # timeout-capped probe

    # npm doctor — timeout-capped; served by the parallel prefetch when
    # doctor.sh warmed it, run inline on the same cap otherwise (#101).
    local npm_doctor_log _np_rc=0
    npm_doctor_log="$(mdoctor_mktemp_file npm-doctor)"
    perf_probe_capture npm_doctor "$npm_doctor_log" || _np_rc=$?
    if [ "$_np_rc" -eq 0 ]; then
      status_ok "npm doctor passed."   # probe ran timeout-capped
    elif [ "$_np_rc" -eq 124 ]; then
      status_info "npm doctor timed out (timeout ${MDOCTOR_REGISTRY_TIMEOUT_S}s) — skipped."
    else
      status_warn "npm doctor reported issues – see ${npm_doctor_log}."   # timeout-capped probe
      add_action "Review npm issues in ${npm_doctor_log} and fix reported problems (permissions, PATH, etc.)."   # npm probes are timeout-capped
    fi
    add_log_file "$npm_doctor_log" "npm doctor output"   # timeout-capped probe

    # outdated global packages – save full list (timeout-capped probe)
    local npm_out_file _no_rc=0
    npm_out_file="$(mdoctor_mktemp_file npm-outdated-global)"
    perf_probe_capture npm_outdated "$npm_out_file" || _no_rc=$?

    if [ "$_no_rc" -eq 124 ]; then
      status_info "npm outdated timed out (timeout ${MDOCTOR_REGISTRY_TIMEOUT_S}s) — skipped."
    else
      # Count excluding header line (if present)
      local count
      if grep -qE 'Package|Current|Wanted|Latest' "$npm_out_file" 2>/dev/null; then
        count=$(tail -n +2 "$npm_out_file" 2>/dev/null | wc -l | tr -d ' ')
      else
        count=$(wc -l <"$npm_out_file" 2>/dev/null | tr -d ' ')
      fi

      if [[ -z "$count" ]] || [[ "$count" == "0" ]]; then
        status_ok "No outdated global npm packages (or none installed)."   # timeout-capped probe
      else
        status_warn "${count} outdated global npm package(s)."   # timeout-capped probe
        status_info "Sample outdated global npm packages:"   # timeout-capped probe
        head -n 5 "$npm_out_file" | sed 's/^/    - /'
        [ "$count" -gt 5 ] && status_info "    … see full list in ${npm_out_file}"

        add_action "Update global npm packages (audit probes are timeout-capped):
         - List outdated: 'npm' 'outdated' '-g' '--depth=0'
         - Update all:   'npm' 'update' '-g'
         - Or update specific packages: 'npm' 'update' '-g' '<package>'
         Full outdated list: ${npm_out_file}
         For project-specific deps, run 'npm' 'outdated' in each project directory."

        add_log_file "$npm_out_file" "Outdated global npm packages"   # timeout-capped probe
      fi
    fi
  else
    status_warn "npm not found."   # npm probes are timeout-capped when present
    if [ "$has_node" = true ]; then
      add_action "npm missing but Node is installed – reinstall Node.js or ensure npm is on PATH."   # timeout-capped probes
    fi
  fi
}
