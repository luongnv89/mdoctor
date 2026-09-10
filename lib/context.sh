#!/usr/bin/env bash
#
# lib/context.sh
# Explicit module context initializer (Task 9.1). Hidden globals are the
# de-facto parameter list of all 53 check/cleanup/fix modules, which take
# zero arguments — this file is the one greppable place declaring every
# required input with its type and default. All three entry points
# (mdoctor, cleanup.sh, doctor.sh) call mdoctor_context_init before sourcing
# any module; a module sourced without the initializer fails loudly naming
# _MDOCTOR_CONTEXT_READY instead of running with wrong defaults.
#
# No dependencies — source this file before every other lib file.
#

# Guard against double-sourcing (the initializer itself is idempotent).
if [ "${_MDOCTOR_CONTEXT_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_CONTEXT_LOADED=true

# Module context contract — all 11 inputs (name: type = default):
#   DRY_RUN        bool = true    fail-closed: only an explicit false deletes
#   DAYS_OLD       int = 7        staleness threshold (DAYS_OLD_OVERRIDE wins)
#   LOGFILE        path = ""      run log; each entry point sets its own file
#   STEP_CURRENT   int = 0        progress numerator for the spinner
#   STEP_TOTAL     int = 1        progress denominator for the spinner
#   MDOCTOR_DEBUG  bool = false   structured debug diagnostics switch
#   ACTIONS        array = ()     actionable next steps collected per run
#   WARN_COUNT     int = 0        warning tally for the health score
#   FAIL_COUNT     int = 0        failure tally for the health score
#   LOG_PATHS      array = ()     detailed log files generated in this run
#   LOG_DESCS      array = ()     one description per LOG_PATHS entry
#
# mdoctor_context_init — declare the contract with defaults. Safe to call
# more than once; marks _MDOCTOR_CONTEXT_READY=true last.
mdoctor_context_init() {
  # shellcheck disable=SC2034
  DRY_RUN=true
  # shellcheck disable=SC2034
  DAYS_OLD="${DAYS_OLD_OVERRIDE:-7}"
  # shellcheck disable=SC2034
  LOGFILE="${LOGFILE:-}"
  # shellcheck disable=SC2034
  STEP_CURRENT=0
  # shellcheck disable=SC2034
  STEP_TOTAL=1
  # shellcheck disable=SC2034
  MDOCTOR_DEBUG="${MDOCTOR_DEBUG:-false}"
  # shellcheck disable=SC2034
  ACTIONS=()
  # shellcheck disable=SC2034
  WARN_COUNT=0
  # shellcheck disable=SC2034
  FAIL_COUNT=0
  # shellcheck disable=SC2034
  LOG_PATHS=()
  # shellcheck disable=SC2034
  LOG_DESCS=()

  _MDOCTOR_CONTEXT_READY=true
  export _MDOCTOR_CONTEXT_READY
}
