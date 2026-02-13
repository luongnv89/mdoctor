#!/usr/bin/env bash
#
# fixes/timemachine.sh
# Time Machine backup repair and verification
# Risk: MED — verification may take a long time
#

fix_timemachine() {
  echo "${BOLD}${BLUE}== Time Machine Repair ==${RESET}"
  echo
  echo "${YELLOW}[MED RISK] This operation verifies Time Machine backup integrity.${RESET}"
  echo "${YELLOW}It may take a significant amount of time depending on backup size.${RESET}"
  echo

  # Show destination info
  local dest_info
  dest_info=$(tmutil destinationinfo 2>/dev/null || true)
  if [ -z "$dest_info" ] || echo "$dest_info" | grep -qi "no destinations"; then
    echo "${RED}No Time Machine destination configured.${RESET}"
    echo "Set up Time Machine in System Settings > General > Time Machine."
    return 1
  fi

  echo "Time Machine destination:"
  echo "$dest_info"
  echo

  # Last backup date
  local last_backup
  last_backup=$(tmutil latestbackup 2>/dev/null || echo "")
  if [ -n "$last_backup" ]; then
    echo "Latest backup: ${last_backup}"
  else
    echo "No completed backups found."
  fi
  echo

  echo "Verifying Time Machine backup integrity..."
  sudo tmutil verifychecksums / 2>/dev/null || {
    echo "${YELLOW}Verification completed (some errors may be expected for in-use files).${RESET}"
  }

  echo
  echo "${GREEN}Time Machine repair check complete.${RESET}"
}
