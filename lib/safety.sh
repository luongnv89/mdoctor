#!/usr/bin/env bash
#
# lib/safety.sh
# Centralized deletion safety primitives for cleanup operations
#

# Error codes
MDOCTOR_SAFE_ERR_INVALID_PATH=21
MDOCTOR_SAFE_ERR_PROTECTED_PATH=22
MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED=23
MDOCTOR_SAFE_ERR_REMOVE_FAILED=24

_safety_log() {
  if declare -f log >/dev/null 2>&1; then
    log "$*"
  else
    echo "$*"
  fi
}

_normalize_path() {
  local path="${1-}"

  if [ -z "$path" ]; then
    echo ""
    return 0
  fi

  # Keep / intact, trim trailing slash otherwise
  if [ "$path" != "/" ]; then
    while [ "${path%/}" != "$path" ]; do
      path="${path%/}"
    done
  fi

  echo "$path"
}

is_protected_deletion_path() {
  local path
  path="$(_normalize_path "${1-}")"

  case "$path" in
    /|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/usr/lib|/System|/private|/private/etc|/private/var|/etc|/var|/Library|/Applications)
      return 0
      ;;
    /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/usr/lib/*|/System/*|/private/etc/*|/private/var/*|/etc/*|/var/*)
      return 0
      ;;
  esac

  if [ -n "${HOME:-}" ]; then
    case "$path" in
      "$HOME"|"$HOME/Desktop"|"$HOME/Documents"|"$HOME/Library"|"$HOME/.ssh"|"$HOME/.gnupg")
        return 0
        ;;
    esac
  fi

  return 1
}

validate_deletion_path() {
  local raw_path="${1-}"
  local path
  path="$(_normalize_path "$raw_path")"

  if [ -z "$path" ]; then
    _safety_log "[SAFE] invalid deletion path: empty"
    return "$MDOCTOR_SAFE_ERR_INVALID_PATH"
  fi

  case "$path" in
    /*) ;;
    *)
      _safety_log "[SAFE] invalid deletion path (must be absolute): $path"
      return "$MDOCTOR_SAFE_ERR_INVALID_PATH"
      ;;
  esac

  if [[ "$path" =~ (^|/)\.\.(/|$) ]]; then
    _safety_log "[SAFE] invalid deletion path (traversal detected): $path"
    return "$MDOCTOR_SAFE_ERR_INVALID_PATH"
  fi

  if [[ "$path" == *$'\n'* ]] || [[ "$path" == *$'\r'* ]] || [[ "$path" == *$'\t'* ]]; then
    _safety_log "[SAFE] invalid deletion path (control chars): $path"
    return "$MDOCTOR_SAFE_ERR_INVALID_PATH"
  fi

  if is_protected_deletion_path "$path"; then
    _safety_log "[SAFE] blocked protected path: $path"
    return "$MDOCTOR_SAFE_ERR_PROTECTED_PATH"
  fi

  return 0
}

safe_remove() {
  local path="${1-}"
  local allow_symlink=false

  if [ "${2-}" = "--allow-symlink" ]; then
    allow_symlink=true
  fi

  validate_deletion_path "$path" || return $?

  if [ -L "$path" ] && [ "$allow_symlink" != true ]; then
    _safety_log "[SAFE] blocked symlink removal (use --allow-symlink): $path"
    return "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED"
  fi

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi

  if [ "${DRY_RUN:-true}" = true ]; then
    _safety_log "[DRY RUN][SAFE_REMOVE] $path"
    return 0
  fi

  rm -rf -- "$path"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _safety_log "[SAFE][ERROR] failed to remove path (exit $rc): $path"
    return "$MDOCTOR_SAFE_ERR_REMOVE_FAILED"
  fi

  _safety_log "[SAFE][REMOVED] $path"
  return 0
}

safe_remove_children() {
  local dir="${1-}"
  local allow_symlink=false

  if [ "${2-}" = "--allow-symlink" ]; then
    allow_symlink=true
  fi

  validate_deletion_path "$dir" || return $?

  if [ ! -d "$dir" ]; then
    return 0
  fi

  local rc=0
  local item
  for item in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$item" ] || [ -L "$item" ] || continue
    if [ "$allow_symlink" = true ]; then
      safe_remove "$item" --allow-symlink || rc=$?
    else
      safe_remove "$item" || rc=$?
    fi
  done

  return "$rc"
}

safe_find_delete() {
  local base_dir="${1-}"
  shift || true

  validate_deletion_path "$base_dir" || return $?

  if [ ! -d "$base_dir" ]; then
    return 0
  fi

  local -a find_cmd
  find_cmd=(find "$base_dir")

  if [ "$#" -gt 0 ]; then
    find_cmd+=("$@")
  else
    find_cmd+=(-mindepth 1)
  fi

  find_cmd+=(-print0)

  local count=0
  local rc=0
  local match=""

  while IFS= read -r -d '' match; do
    count=$((count + 1))
    safe_remove "$match" --allow-symlink || rc=$?
  done < <("${find_cmd[@]}" 2>/dev/null)

  if [ "$count" -eq 0 ]; then
    _safety_log "[SAFE] no deletion candidates in: $base_dir"
  fi

  return "$rc"
}
