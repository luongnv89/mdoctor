#!/usr/bin/env bash
#
# fixes/audio.sh
# Restart Core Audio daemon
# Risk: LOW — fixes no-sound, crackling, wrong output device
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required fixes inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
fix_audio() {
  header "Fixing Audio"

  if ! is_macos; then
    echo "${YELLOW}Audio fix is macOS-only (Core Audio) — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  echo "Restarting Core Audio daemon..."
  if run_cmd_args sudo killall coreaudiod 2>/dev/null; then
    status_ok "Core Audio daemon restarted. Audio should resume shortly."
    echo "If the issue persists, check System Settings > Sound for output device."
    return 0
  else
    status_warn "Could not restart Core Audio daemon."
    return 1
  fi
}
