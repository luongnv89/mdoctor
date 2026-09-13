#!/usr/bin/env bash
#
# checks/devtools.sh
# Developer tools checks (Xcode, Git, Docker)
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
check_dev_tools() {
  step "Developer Tools, Git & Docker"

  # Build tools — every tool probe is timeout-capped (issue #101): a
  # wrapper shim or daemon-adjacent tool can otherwise stall the module.
  if is_macos; then
    local _xc_out="" _xc_rc=0
    _xc_out=$(mdoctor_timeout "$MDOCTOR_CMD_TIMEOUT_S" xcode-select -p 2>/dev/null) || _xc_rc=$?
    if [ "$_xc_rc" -eq 0 ]; then
      status_ok "Xcode Command Line Tools installed: ${_xc_out}"
    elif [ "$_xc_rc" -eq 124 ]; then
      status_info "Xcode CLT probe timed out (timeout ${MDOCTOR_CMD_TIMEOUT_S}s) — status unknown."
    else
      status_warn "Xcode Command Line Tools not found."
      add_action "Install Xcode Command Line Tools: run 'xcode-select --install'."
    fi
  else
    # Linux: build-essential, gcc, make — tcap_or keeps a timed-out probe
    # visible in the version column instead of printing nothing (#101).
    if command -v gcc >/dev/null 2>&1; then
      status_ok "GCC: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" gcc --version | head -n1)"
    elif command -v cc >/dev/null 2>&1; then
      status_ok "C compiler: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" cc --version | head -n1)"
    else
      status_info "No C compiler found."
      add_action "Install build tools: sudo apt install build-essential"
    fi
    if command -v make >/dev/null 2>&1; then
      status_ok "Make: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" make --version | head -n1)"
    fi
  fi

  # Git
  if command -v git >/dev/null 2>&1; then
    status_ok "Git: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" git --version)"
  else
    status_warn "Git not found."
    if is_macos; then
      add_action "Install Git via Xcode CLT ('xcode-select --install') or 'brew' 'install' 'git'."
    else
      add_action "Install Git: sudo apt install git"
    fi
  fi

  # Docker — the run's single docker info probe, timeout-capped (issue
  # #101): one capture serves this module and check_containers; the
  # prefetch usually answered it before this module ran. Timeout is
  # MDOCTOR_DOCKER_TIMEOUT_S — a hung daemon reports "timed out".
  if command -v docker >/dev/null 2>&1; then
    local docker_info_log _di_rc=0
    docker_info_log="$(mdoctor_mktemp_file docker-info)"
    perf_capture_docker_info || _di_rc=$?
    printf '%s\n' "${_PERF_DOCKER_INFO:-}" >"$docker_info_log"
    if [ "$_di_rc" -eq 0 ]; then
      status_ok "Docker is installed and daemon is reachable."   # timeout-capped probe
    elif [ "$_di_rc" -eq 124 ]; then
      status_info "docker info timed out (timeout ${MDOCTOR_DOCKER_TIMEOUT_S}s) — daemon did not answer."
    else
      status_warn "Docker CLI found but daemon not reachable."
      add_action "Start Docker Desktop or ensure the Docker daemon is running, then re-run the 'docker' 'info' probe."
    fi
    add_log_file "$docker_info_log" "Docker info output"
  else
    status_info "Docker not installed (skipping)."
  fi
}
