#!/usr/bin/env bash
#
# fixes/pacman.sh
# Pacman package manager fix
# Risk: LOW
# Platform: Linux (Arch-family, including Omarchy) only
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
fix_pacman() {
  header "Pacman Package Manager Fix"

  local step_rc=0

  if ! command -v pacman >/dev/null 2>&1; then
    echo "Pacman not available on this system."
    # Honest failure (issue #220, same class as #111 in fixes/dns.sh):
    # nothing ran, so nothing was fixed. Only an actual apply (force) may
    # fail here: a dry run performs no work, so it must not poison
    # `fix all`'s aggregate rc — the Task 4.4 dry-run contract
    # (tests/test_fix_dry_run.bats) requires `fix all` to exit 0 in
    # dry-run. rc 2 (invalid DRY_RUN) fails closed to dry.
    local _dry_rc=0
    is_dry_run || _dry_rc=$?
    if [ "$_dry_rc" -eq 1 ]; then
      return 1
    fi
    return 0
  fi

  echo "Refreshing keyring..."
  run_cmd_args sudo pacman -S --needed --noconfirm archlinux-keyring || step_rc=$?

  echo "Upgrading packages..."
  run_cmd_args sudo pacman -Syu --noconfirm || step_rc=$?

  # Unmerged configs are read-only findings, never auto-merged.
  local _pacnew="" _pn_rc=0
  _pacnew=$(find /etc -name '*.pacnew' -o -name '*.pacsave' 2>/dev/null) || _pn_rc=$?
  if [ "$_pn_rc" -ne 0 ]; then
    _pacnew=""
  fi
  if [ -n "$_pacnew" ]; then
    echo
    echo "Unmerged config files found (merge them with 'pacdiff'):"
    printf '%s\n' "$_pacnew"
  fi

  echo
  if [ "$step_rc" -eq 0 ]; then
    status_ok "Pacman package manager fix complete."
    return 0
  else
    status_warn "Pacman fix reported errors (see above)."
    return 1
  fi
}
