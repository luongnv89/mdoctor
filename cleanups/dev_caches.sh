#!/usr/bin/env bash
#
# cleanups/dev_caches.sh
# Developer caches cleanup with size reporting
# Risk: LOW
#
# Cleans package manager caches, build caches, and stale node_modules.
# Reports size of each cache before cleaning.
#

# How many days before a node_modules is considered stale
NODE_MODULES_DAYS="${NODE_MODULES_DAYS:-30}"

clean_dev_caches() {
  header "Developer caches cleanup"

  local total_kb=0

  # Helper: measure, log, and clean a cache directory
  # Usage: _clean_cache "Label" "/path/to/cache"
  _clean_cache() {
    local label="$1"
    local cache_dir="$2"

    if [ -d "$cache_dir" ]; then
      local sz_kb
      sz_kb=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
      sz_kb="${sz_kb:-0}"

      if (( sz_kb > 0 )); then
        local sz_hr
        sz_hr=$(kb_to_human "$sz_kb")
        log "${label}: ${sz_hr} (${cache_dir})"
        safe_remove_children "${cache_dir}" || true
        total_kb=$((total_kb + sz_kb))
      else
        log "${label}: empty, skipping."
      fi
    fi
  }

  # ── npm ──
  _clean_cache "npm cache" "${HOME}/.npm"
  _clean_cache "npm cache (Library)" "${HOME}/Library/Caches/npm"

  # ── Yarn ──
  _clean_cache "Yarn cache" "${HOME}/Library/Caches/Yarn"
  _clean_cache "Yarn cache (v2+)" "${HOME}/.yarn/cache"

  # ── pnpm ──
  _clean_cache "pnpm store" "${HOME}/Library/pnpm/store"
  _clean_cache "pnpm store (XDG)" "${HOME}/.local/share/pnpm/store"

  # ── pip ──
  _clean_cache "pip cache" "${HOME}/Library/Caches/pip"
  _clean_cache "pip cache (XDG)" "${HOME}/.cache/pip"

  # ── Conda packages ──
  _clean_cache "Conda packages (miniconda3)" "${HOME}/miniconda3/pkgs"
  _clean_cache "Conda packages (anaconda3)" "${HOME}/anaconda3/pkgs"

  # ── Homebrew ──
  _clean_cache "Homebrew cache" "${HOME}/Library/Caches/Homebrew"

  # ── Maven ──
  _clean_cache "Maven repository" "${HOME}/.m2/repository"

  # ── Gradle ──
  _clean_cache "Gradle caches" "${HOME}/.gradle/caches"

  # ── Go modules ──
  _clean_cache "Go module cache" "${HOME}/go/pkg/mod/cache"

  # ── Cargo ──
  _clean_cache "Cargo registry cache" "${HOME}/.cargo/registry/cache"

  # ── CocoaPods ──
  _clean_cache "CocoaPods cache" "${HOME}/Library/Caches/CocoaPods"

  # ── Xcode DerivedData ──
  _clean_cache "Xcode DerivedData" "${HOME}/Library/Developer/Xcode/DerivedData"

  # ── Docker ──
  if command -v docker >/dev/null 2>&1; then
    log "Docker detected – pruning unused data."
    run_cmd_args docker system prune -af --volumes
  else
    log "Docker not found; skipping."
  fi

  # ── Stale node_modules ──
  log "Scanning for stale node_modules (unused >${NODE_MODULES_DAYS} days)..."

  local search_dirs=()
  local d

  if declare -f cleanup_scope_get_search_dirs >/dev/null 2>&1; then
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      [ -d "$d" ] && search_dirs+=("$d")
    done < <(cleanup_scope_get_search_dirs)
  else
    for d in "${HOME}/Projects" "${HOME}/projects" "${HOME}/code" "${HOME}/workspace" "${HOME}/dev" "${HOME}/src"; do
      [ -d "$d" ] && search_dirs+=("$d")
    done
  fi

  if (( ${#search_dirs[@]} > 0 )); then
    local nm_count=0
    local nm_total_kb=0

    for search_dir in "${search_dirs[@]}"; do
      while IFS= read -r nm_dir; do
        [ -z "$nm_dir" ] && continue

        if declare -f cleanup_scope_is_excluded >/dev/null 2>&1 && cleanup_scope_is_excluded "$nm_dir"; then
          local nm_skip
          nm_skip="${nm_dir/#$HOME/~}"
          log "Skipping node_modules by cleanup scope: ${nm_skip}"
          continue
        fi

        local nm_sz
        nm_sz=$(du -sk "$nm_dir" 2>/dev/null | awk '{print $1}')
        nm_sz="${nm_sz:-0}"
        if (( nm_sz > 0 )); then
          local nm_hr
          nm_hr=$(kb_to_human "$nm_sz")
          local nm_parent
          nm_parent=$(dirname "$nm_dir")
          nm_parent="${nm_parent/#$HOME/~}"
          log "Stale node_modules: ${nm_hr} — ${nm_parent}"
          safe_remove "${nm_dir}" || true
          nm_total_kb=$((nm_total_kb + nm_sz))
          nm_count=$((nm_count + 1))
        fi
      done < <(timeout 60 find "${search_dir}" -maxdepth 5 -type d -name "node_modules" -not -path "*/node_modules/*/node_modules" -mtime "+${NODE_MODULES_DAYS}" 2>/dev/null)
    done

    if (( nm_count > 0 )); then
      local nm_total_hr
      nm_total_hr=$(kb_to_human "$nm_total_kb")
      log "Stale node_modules cleaned: ${nm_count} directories, ${nm_total_hr}"
      total_kb=$((total_kb + nm_total_kb))
    else
      log "No stale node_modules found (threshold: ${NODE_MODULES_DAYS} days)."
    fi
  else
    log "No common project directories found; skipping node_modules scan."
  fi

  # ── Summary ──
  if (( total_kb > 0 )); then
    local total_hr
    total_hr=$(kb_to_human "$total_kb")
    log "Developer caches cleanup total: ${total_hr}"
  else
    log "Developer caches cleanup: nothing to clean."
  fi

  # Unset the helper function to avoid polluting the namespace
  unset -f _clean_cache
}
