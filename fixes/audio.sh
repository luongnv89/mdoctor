#!/usr/bin/env bash
#
# fixes/audio.sh
# Restart Core Audio daemon
# Risk: LOW — fixes no-sound, crackling, wrong output device
#

fix_audio() {
  echo "${BOLD}${BLUE}== Fixing Audio ==${RESET}"
  echo

  if ! is_macos; then
    echo "${YELLOW}Audio fix is macOS-only (Core Audio) — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  echo "Restarting Core Audio daemon..."
  sudo killall coreaudiod 2>/dev/null || true

  echo "${GREEN}Core Audio daemon restarted. Audio should resume shortly.${RESET}"
  echo "If the issue persists, check System Settings > Sound for output device."
}
