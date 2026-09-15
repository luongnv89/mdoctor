#!/usr/bin/env bash
#
# lib/cleanup_scope.sh
# Custom include/exclude scope for cleanup scans
#

MDOCTOR_CLEANUP_SCOPE_FILE="${MDOCTOR_CLEANUP_SCOPE_FILE:-${HOME}/.config/mdoctor/cleanup_scope.conf}"

_MDOCTOR_SCOPE_LOADED=false
_MDOCTOR_SCOPE_INCLUDE_PATHS=()
_MDOCTOR_SCOPE_EXCLUDE_GLOBS=()

_mdoctor_scope_default_dirs() {
  printf '%s\n' \
    "${HOME}/Projects" \
    "${HOME}/projects" \
    "${HOME}/code" \
    "${HOME}/workspace" \
    "${HOME}/dev" \
    "${HOME}/src"
}

ensure_cleanup_scope_file() {
  local file="$MDOCTOR_CLEANUP_SCOPE_FILE"
  local dir
  dir="$(dirname "$file")"

  # Best-effort state (issue #113): an unwritable config dir warns and
  # continues — under `set -e` an unchecked mkdir/chmod here used to
  # abort the whole run. A missing scope file just means default scope.
  if [ ! -d "$dir" ]; then
    if ! mkdir -p "$dir" 2>/dev/null; then
      echo "warning: cannot create config dir '${dir}' — cleanup scope config unavailable" >&2
      return 0
    fi
    # Task 3.4: state is private (0700 dirs, 0600 files).
    chmod 700 "$dir" 2>/dev/null || true
  fi
  if [ ! -f "$file" ]; then
    if cat >"$file" 2>/dev/null <<'EOF'
# mdoctor cleanup scope configuration
#
# Optional include paths for stale node_modules scan.
# When INCLUDE_PATH lines are present, they override default scan roots.
#
# Format:
#   INCLUDE_PATH=~/workspace
#   EXCLUDE_GLOB=*keep-project*/node_modules*
#
# Notes:
# - A leading ~ is expanded to your home directory; a tilde anywhere
#   else in the path stays literal.
# - EXCLUDE_GLOB uses shell-style glob matching against full candidate path.
# - Keep file minimal; one rule per line.

# INCLUDE_PATH=~/workspace
# INCLUDE_PATH=~/Projects
# EXCLUDE_GLOB=*node_modules/.cache*
EOF
    then
      chmod 600 "$file" 2>/dev/null || true
    else
      echo "warning: cannot create cleanup scope file '${file}' — using default scope" >&2
    fi
  fi
}

load_cleanup_scope() {
  if is_truthy "$_MDOCTOR_SCOPE_LOADED"; then
    return 0
  fi

  ensure_cleanup_scope_file

  _MDOCTOR_SCOPE_INCLUDE_PATHS=()
  _MDOCTOR_SCOPE_EXCLUDE_GLOBS=()

  # Issue #113: when the config dir could not be created there is no file
  # to read — `done < missing` would error and abort under `set -e`. An
  # absent scope file means default scope.
  if [ ! -f "$MDOCTOR_CLEANUP_SCOPE_FILE" ]; then
    _MDOCTOR_SCOPE_LOADED=true
    return 0
  fi
  if [ ! -r "$MDOCTOR_CLEANUP_SCOPE_FILE" ]; then
    echo "warning: cleanup scope file '${MDOCTOR_CLEANUP_SCOPE_FILE}' is unreadable — using default scope" >&2
    _MDOCTOR_SCOPE_LOADED=true
    return 0
  fi

  local line=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
    esac

    case "$line" in
      INCLUDE_PATH=*)
        local p="${line#INCLUDE_PATH=}"
        p="${p/#\~/$HOME}"
        [ -n "$p" ] && _MDOCTOR_SCOPE_INCLUDE_PATHS+=("$p")
        ;;
      EXCLUDE_GLOB=*)
        local g="${line#EXCLUDE_GLOB=}"
        g="${g/#\~/$HOME}"
        [ -n "$g" ] && _MDOCTOR_SCOPE_EXCLUDE_GLOBS+=("$g")
        ;;
    esac
  done <"$MDOCTOR_CLEANUP_SCOPE_FILE"

  _MDOCTOR_SCOPE_LOADED=true
}

# cleanup_scope_get_search_dirs — dirs the dev_caches scan walks:
# INCLUDE_PATH lines when configured, else the default candidate list.
# Each physical directory is emitted once: on a case-insensitive
# filesystem (default APFS) "${HOME}/projects" resolves to the same
# directory as "${HOME}/Projects", and a doubled root would be traversed
# once per spelling — double-counting every node_modules match (issue
# #204; same dedup as checks/storage.sh::_storage_search_dirs, #97).
# device:inode keys (stat -L, so symlinks alias too) are spelling-proof.
# A candidate that cannot be stat'd (e.g. does not exist) yields no key
# and passes through — the consumer owns the [ -d ] filter.
cleanup_scope_get_search_dirs() {
  load_cleanup_scope

  local d key s
  local -a seen=()
  {
    if [ "${#_MDOCTOR_SCOPE_INCLUDE_PATHS[@]}" -gt 0 ]; then
      printf '%s\n' "${_MDOCTOR_SCOPE_INCLUDE_PATHS[@]}"
    else
      _mdoctor_scope_default_dirs
    fi
  } | while IFS= read -r d; do
    [ -z "$d" ] && continue
    key="$(stat -Lc '%d:%i' "$d" 2>/dev/null || stat -Lf '%d:%i' "$d" 2>/dev/null)"
    if [ -n "$key" ]; then
      for s in ${seen[@]+"${seen[@]}"}; do
        [ "$s" = "$key" ] && continue 2
      done
      seen+=("$key")
    fi
    printf '%s\n' "$d"
  done
}

cleanup_scope_is_excluded() {
  local path="${1-}"
  [ -z "$path" ] && return 1

  load_cleanup_scope

  if [ "${#_MDOCTOR_SCOPE_EXCLUDE_GLOBS[@]}" -eq 0 ]; then
    return 1
  fi

  local pat=""
  for pat in "${_MDOCTOR_SCOPE_EXCLUDE_GLOBS[@]}"; do
    # shellcheck disable=SC2254 # exclude entries ARE globs by design (EXCLUDE_GLOB=); quoting would break matching
    case "$path" in
      $pat) return 0 ;;
    esac
  done

  return 1
}
