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
    run_cmd "brew cleanup -s"
    run_cmd "brew autoremove"
  else
    log "Homebrew not found; skipping."
  fi

  # Common language/tool caches (pip, npm, yarn, pnpm)
  if [ -d "${HOME}/Library/Caches/pip" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/pip\"/*"
  fi
  if [ -d "${HOME}/.cache/pip" ]; then
    run_cmd "rm -rf \"${HOME}/.cache/pip\"/*"
  fi
  if [ -d "${HOME}/.npm" ]; then
    run_cmd "rm -rf \"${HOME}/.npm\"/*"
  fi
  if [ -d "${HOME}/Library/Caches/npm" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/npm\"/*"
  fi
  if [ -d "${HOME}/Library/Caches/Yarn" ]; then
    run_cmd "rm -rf \"${HOME}/Library/Caches/Yarn\"/*"
  fi
  if [ -d "${HOME}/Library/pnpm/store" ]; then
    run_cmd "rm -rf \"${HOME}/Library/pnpm/store\"/*"
  fi

  # Docker (removes ALL unused containers/images/volumes)
  if command -v docker >/dev/null 2>&1; then
    log "Docker detected – pruning unused data."
    run_cmd "docker system prune -af --volumes"
  else
    log "Docker not found; skipping."
  fi

  # Note: Xcode cleanup moved to cleanups/xcode.sh (dedicated module)
}
