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
#   DAYS_OLD       int = <module>  staleness threshold; unset = module's own
#                                  default (7/30/90 per cleanups/*.sh);
#                                  DAYS_OLD_OVERRIDE wins when set
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
  # Scalars are exported: every module in checks/, cleanups/ and fixes/
  # consumes them cross-file, which is exactly what the export declares.
  export DRY_RUN=true
  # Issue #94: export DAYS_OLD only when an override is present so each
  # cleanups/* module keeps its own documented ${DAYS_OLD:-N} default
  # reachable (a force-exported 7 shadowed the 30/90 module defaults).
  if [ -n "${DAYS_OLD_OVERRIDE:-}" ]; then
    export DAYS_OLD="${DAYS_OLD_OVERRIDE}"
  fi
  export LOGFILE="${LOGFILE:-}"
  export STEP_CURRENT=0
  export STEP_TOTAL=1
  export MDOCTOR_DEBUG="${MDOCTOR_DEBUG:-false}"
  export WARN_COUNT=0
  export FAIL_COUNT=0
  ACTIONS=()
  LOG_PATHS=()
  LOG_DESCS=()
  # Arrays cannot be meaningfully exported; reference them so the
  # declaration site is warning-clean without suppressions. The
  # ${arr[@]+"${arr[@]}"} form is the Bash 3.2-safe empty-array expansion.
  : "${ACTIONS[@]+"${ACTIONS[@]}"}" "${LOG_PATHS[@]+"${LOG_PATHS[@]}"}" "${LOG_DESCS[@]+"${LOG_DESCS[@]}"}"

  _MDOCTOR_CONTEXT_READY=true
  export _MDOCTOR_CONTEXT_READY
}
