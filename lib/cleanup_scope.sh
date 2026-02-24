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

  mkdir -p "$dir"
  if [ ! -f "$file" ]; then
    cat >"$file" <<'EOF'
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
# - ~ is expanded to your home directory.
# - EXCLUDE_GLOB uses shell-style glob matching against full candidate path.
# - Keep file minimal; one rule per line.

# INCLUDE_PATH=~/workspace
# INCLUDE_PATH=~/Projects
# EXCLUDE_GLOB=*node_modules/.cache*
EOF
  fi
}

load_cleanup_scope() {
  if [ "$_MDOCTOR_SCOPE_LOADED" = true ]; then
    return 0
  fi

  ensure_cleanup_scope_file

  _MDOCTOR_SCOPE_INCLUDE_PATHS=()
  _MDOCTOR_SCOPE_EXCLUDE_GLOBS=()

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

cleanup_scope_get_search_dirs() {
  load_cleanup_scope

  if [ "${#_MDOCTOR_SCOPE_INCLUDE_PATHS[@]}" -gt 0 ]; then
    printf '%s\n' "${_MDOCTOR_SCOPE_INCLUDE_PATHS[@]}"
  else
    _mdoctor_scope_default_dirs
  fi
}

cleanup_scope_is_excluded() {
  local path="${1-}"
  [ -z "$path" ] && return 1

  load_cleanup_scope

  local pat=""
  for pat in "${_MDOCTOR_SCOPE_EXCLUDE_GLOBS[@]}"; do
    case "$path" in
      $pat) return 0 ;;
    esac
  done

  return 1
}
