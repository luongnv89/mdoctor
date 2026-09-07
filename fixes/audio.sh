#!/usr/bin/env bash
#
# fixes/audio.sh
# Restart Core Audio daemon
# Risk: LOW — fixes no-sound, crackling, wrong output device
#

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
