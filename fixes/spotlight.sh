#!/usr/bin/env bash
#
# fixes/spotlight.sh
# Rebuild Spotlight index
# Risk: MED
#

fix_spotlight() {
  header "Rebuilding Spotlight Index"

  if ! is_macos; then
    echo "${YELLOW}Spotlight fix is macOS-only (mdutil) — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  local step_rc=0

  echo "Turning Spotlight off..."
  run_cmd_args sudo mdutil -a -i off 2>/dev/null || step_rc=$?

  echo "Erasing Spotlight index..."
  run_cmd_args sudo mdutil -E / 2>/dev/null || step_rc=$?

  echo "Turning Spotlight back on..."
  run_cmd_args sudo mdutil -a -i on 2>/dev/null || step_rc=$?

  if [ "$step_rc" -eq 0 ]; then
    status_ok "Spotlight index rebuild initiated. This may take a while in the background."
    return 0
  else
    status_warn "Spotlight rebuild reported errors (see above)."
    return 1
  fi
}
