#!/usr/bin/env bash
#
# cleanups/dev.sh
# Developer tools cleanup
#

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
  if [ -d "${HOME}/Library/Caches/pip" ]; then
    safe_remove_children "${HOME}/Library/Caches/pip" || true
  fi
  if [ -d "${HOME}/.cache/pip" ]; then
    safe_remove_children "${HOME}/.cache/pip" || true
  fi
  if [ -d "${HOME}/.npm" ]; then
    safe_remove_children "${HOME}/.npm" || true
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

  # Docker (removes ALL unused containers/images/volumes)
  if command -v docker >/dev/null 2>&1; then
    log "Docker detected – pruning unused data."
    run_cmd_args docker system prune -af --volumes
  else
    log "Docker not found; skipping."
  fi

  # Note: Xcode cleanup moved to cleanups/xcode.sh (dedicated module)
}
