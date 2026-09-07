#!/usr/bin/env bash
#
# fixes/timemachine.sh
# Time Machine backup repair and verification
# Risk: MED — verification may take a long time
#

fix_timemachine() {
  header "Time Machine Repair"

  if ! is_macos; then
    echo "${YELLOW}Time Machine fix is macOS-only (tmutil) — skipping on $(platform_name).${RESET}" >&2
    return 1
  fi

  echo "${YELLOW}[MED RISK] This operation verifies Time Machine backup integrity.${RESET}"
  echo "${YELLOW}It may take a significant amount of time depending on backup size.${RESET}"
  echo

  # Show destination info (read-only probes)
  local dest_info
  dest_info=$(tmutil destinationinfo 2>/dev/null || true)
  if [ -z "$dest_info" ] || echo "$dest_info" | grep -qi "no destinations"; then
    status_fail "No Time Machine destination configured."
    echo "Set up Time Machine in System Settings > General > Time Machine."
    return 1
  fi

  echo "Time Machine destination:"
  echo "$dest_info"
  echo

  # Last backup date (read-only probe)
  local last_backup
  last_backup=$(tmutil latestbackup 2>/dev/null || echo "")
  if [ -n "$last_backup" ]; then
    echo "Latest backup: ${last_backup}"
  else
    echo "No completed backups found."
  fi
  echo

  echo "Verifying Time Machine backup integrity..."
  if run_cmd_args sudo tmutil verifychecksums / 2>/dev/null; then
    status_ok "Time Machine repair check complete."
    return 0
  else
    status_warn "Verification completed with errors (some are expected for in-use files)."
    return 1
  fi
}
