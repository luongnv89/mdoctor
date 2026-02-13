#!/usr/bin/env bash
#
# fixes/spotlight.sh
# Rebuild Spotlight index
# Risk: MED
#

fix_spotlight() {
  echo "${BOLD}${BLUE}== Rebuilding Spotlight Index ==${RESET}"
  echo

  echo "Turning Spotlight off..."
  sudo mdutil -a -i off 2>/dev/null || true

  echo "Erasing Spotlight index..."
  sudo mdutil -E / 2>/dev/null || true

  echo "Turning Spotlight back on..."
  sudo mdutil -a -i on 2>/dev/null || true

  echo "${GREEN}Spotlight index rebuild initiated. This may take a while in the background.${RESET}"
}
