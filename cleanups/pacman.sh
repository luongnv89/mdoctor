#!/usr/bin/env bash
#
# cleanups/pacman.sh
# Pacman package cache cleanup
# Risk: MED
# Platform: Linux (Arch-family, including Omarchy) only
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
clean_pacman_cache() {
  local rc=0
  header "Pacman cache cleanup"

  if ! command -v pacman >/dev/null 2>&1; then
    log "Pacman not available; skipping."
    return 0
  fi

  # Thin the package cache to the last 3 versions (pacman-contrib).
  if command -v paccache >/dev/null 2>&1; then
    log "Removing old pacman package versions (keeping last 3)..."
    run_cmd_args sudo paccache -r || rc=$?
  else
    log "paccache not found; skipping versioned thinning (install pacman-contrib for finer control)."
  fi

  # Drop cached packages that are no longer installed.
  log "Cleaning pacman package cache..."
  run_cmd_args sudo pacman -Sc --noconfirm || rc=$?

  # AUR helper caches (user-level, no sudo).
  if command -v yay >/dev/null 2>&1; then
    log "Cleaning yay cache..."
    run_cmd_args yay -Sc --noconfirm || rc=$?
  fi
  if command -v paru >/dev/null 2>&1; then
    log "Cleaning paru cache..."
    run_cmd_args paru -Sc --noconfirm || rc=$?
  fi

  # Remove orphan packages (installed as dependencies, no longer required).
  # The orphan query is best-effort: a locked db yields nothing to remove
  # rather than aborting the module (return-code contract, Task 9.3).
  local _orphans="" _oq_rc=0
  _orphans=$(pacman -Qtdq 2>/dev/null) || _oq_rc=$?
  if [ "$_oq_rc" -ne 0 ]; then
    log "Orphan query failed (exit ${_oq_rc}); skipping orphan removal."
    _orphans=""
  fi
  if [ -n "$_orphans" ]; then
    log "Removing orphan packages..."
    local _orphan_args=()
    local _o
    while IFS= read -r _o; do
      [ -n "$_o" ] && _orphan_args+=("$_o")
    done <<< "$_orphans"
    if [ "${#_orphan_args[@]}" -gt 0 ]; then
      run_cmd_args sudo pacman -Rns --noconfirm "${_orphan_args[@]}" || rc=$?
    fi
  else
    log "No orphan packages found."
  fi

  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'pacman' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'pacman')"
  return "$rc"
}
