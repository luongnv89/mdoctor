#!/usr/bin/env bash
#
# cleanups/dev.sh
# Developer tools cleanup
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
clean_dev_stuff() {
  header "Developer / power-user cleanup (Homebrew, language caches, Docker)"

  # Homebrew
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew detected – running cleanup."
    run_cmd_args brew cleanup -s
    run_cmd_args brew autoremove
  else
    log "Homebrew not found; skipping."
  fi

  # Common language/tool caches (pip, npm, yarn, pnpm)
  # Cross-platform paths
  if [ -d "${HOME}/.cache/pip" ]; then
    safe_remove_children "${HOME}/.cache/pip" || true
  fi
  if [ -d "${HOME}/.npm" ]; then
    safe_remove_children "${HOME}/.npm" || true
  fi

  # macOS-specific paths
  if is_macos; then
    if [ -d "${HOME}/Library/Caches/pip" ]; then
      safe_remove_children "${HOME}/Library/Caches/pip" || true
    fi
    if [ -d "${HOME}/Library/Caches/npm" ]; then
      safe_remove_children "${HOME}/Library/Caches/npm" || true
    fi
    if [ -d "${HOME}/Library/Caches/Yarn" ]; then
      safe_remove_children "${HOME}/Library/Caches/Yarn" || true
    fi
    if [ -d "${HOME}/Library/pnpm/store" ]; then
      safe_remove_children "${HOME}/Library/pnpm/store" || true
    fi
  else
    # Linux XDG paths
    if [ -d "${HOME}/.cache/yarn" ]; then
      safe_remove_children "${HOME}/.cache/yarn" || true
    fi
    if [ -d "${HOME}/.local/share/pnpm/store" ]; then
      safe_remove_children "${HOME}/.local/share/pnpm/store" || true
    fi
  fi

  # Docker prune (Task 0.6): `docker system prune -af --volumes` deletes
  # NAMED VOLUMES (database data, not caches), so it sits behind an
  # explicit opt-in and never runs by default.
  if command -v docker >/dev/null 2>&1; then
    if [ "${MDOCTOR_ALLOW_DOCKER_PRUNE:-false}" = true ]; then
      log "Docker detected – pruning unused data (MDOCTOR_ALLOW_DOCKER_PRUNE=true)."
      run_cmd_args docker system prune -af --volumes || true
    else
      log "Docker detected – skipping prune (named volumes are user data, not caches). Set MDOCTOR_ALLOW_DOCKER_PRUNE=true to opt in."
    fi
  else
    log "Docker not found; skipping."
  fi

  # Note: Xcode cleanup moved to cleanups/xcode.sh (dedicated module)
}
