#!/usr/bin/env bash
#
# lib/safety.sh
# Centralized deletion safety primitives for cleanup operations
#

# -----------------------------------------------------------------------------
# Error taxonomy (destructive operations)
# -----------------------------------------------------------------------------
MDOCTOR_SAFE_ERR_INVALID_TARGET=21
MDOCTOR_SAFE_ERR_PROTECTED_TARGET=22
MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED=23
MDOCTOR_SAFE_ERR_PERMISSION_DENIED=24
MDOCTOR_SAFE_ERR_SIP_READONLY=25
MDOCTOR_SAFE_ERR_RUNTIME_FAILURE=26

# Backward-compat aliases (for existing callers)
MDOCTOR_SAFE_ERR_INVALID_PATH="$MDOCTOR_SAFE_ERR_INVALID_TARGET"
MDOCTOR_SAFE_ERR_PROTECTED_PATH="$MDOCTOR_SAFE_ERR_PROTECTED_TARGET"
MDOCTOR_SAFE_ERR_REMOVE_FAILED="$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE"

# Cleanup whitelist config
MDOCTOR_CLEANUP_WHITELIST_FILE="${MDOCTOR_CLEANUP_WHITELIST_FILE:-${HOME}/.config/mdoctor/cleanup_whitelist}"
_MDOCTOR_WHITELIST_LOADED=false
_MDOCTOR_WHITELIST=()

_safety_log() {
  if declare -f log >/dev/null 2>&1; then
    log "$*"
  else
    echo "$*"
  fi
}

safety_error_name() {
  local code="${1:-0}"
  case "$code" in
    21) echo "INVALID_TARGET" ;;
    22) echo "PROTECTED_TARGET" ;;
    23) echo "SYMLINK_BLOCKED" ;;
    24) echo "PERMISSION_DENIED" ;;
    25) echo "SIP_OR_READONLY" ;;
    26) echo "RUNTIME_FAILURE" ;;
    *)  echo "UNKNOWN" ;;
  esac
}

safety_error_hint() {
  local code="${1:-0}"
  local path="${2:-target}"

  case "$code" in
    21)
      echo "Use an absolute, non-traversal path. Re-check computed target: ${path}"
      ;;
    22)
      echo "Target is protected by safety policy. Choose a narrower cache/temp path instead: ${path}"
      ;;
    23)
      echo "Symlink deletion is blocked by default. Use explicit symlink-allow flow only when audited: ${path}"
      ;;
    24)
      echo "Permission denied. Check ownership/permissions, Full Disk Access, or sudo policy for: ${path}"
      ;;
    25)
      echo "Likely SIP/read-only restriction. Avoid protected/system paths or run from writable scope: ${path}"
      ;;
    26)
      echo "Runtime failure. Inspect previous error details and retry with a narrower path: ${path}"
      ;;
    *)
      echo "Unknown failure category. Check logs and command output for details."
      ;;
  esac
}

_safety_error() {
  local code="${1:-$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE}"
  local path="${2:-unknown}"
  local detail="${3:-safety operation failed}"

  local name
  name="$(safety_error_name "$code")"

  _safety_log "[SAFE][ERROR:${name}][code=${code}] ${detail}"
  _safety_log "[SAFE][HINT:${name}] $(safety_error_hint "$code" "$path")"

  if declare -f op_error >/dev/null 2>&1; then
    op_error "$name" "$path" "$detail"
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

ensure_cleanup_whitelist_file() {
  local file="$MDOCTOR_CLEANUP_WHITELIST_FILE"
  local dir
  dir="$(dirname "$file")"

  mkdir -p "$dir"
  if [ ! -f "$file" ]; then
    cat >"$file" <<'EOF'
# mdoctor cleanup whitelist
# One path per line. Blank lines and lines starting with # are ignored.
#
# Rules:
# - Exact path protects that path and its descendants.
# - Use trailing /* to protect descendants of a path.
# - ~ is expanded to your home directory.
#
# Examples:
# ~/.ollama/models
# ~/.cache/huggingface
# ~/.m2/repository/*
EOF
  fi
}

load_cleanup_whitelist() {
  if [ "$_MDOCTOR_WHITELIST_LOADED" = true ]; then
    return 0
  fi

  ensure_cleanup_whitelist_file
  _MDOCTOR_WHITELIST=()

  local line=""
  while IFS= read -r line || [ -n "$line" ]; do
    # trim leading/trailing spaces
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
    esac

    # expand leading ~ only
    line="${line/#\~/$HOME}"
    _MDOCTOR_WHITELIST+=("$line")
  done <"$MDOCTOR_CLEANUP_WHITELIST_FILE"

  _MDOCTOR_WHITELIST_LOADED=true
}

is_whitelisted_cleanup_path() {
  local path
  path="$(_normalize_path "${1-}")"

  [ -z "$path" ] && return 1

  load_cleanup_whitelist

  local entry=""
  local entry_norm=""
  local base=""
  for entry in "${_MDOCTOR_WHITELIST[@]+"${_MDOCTOR_WHITELIST[@]}"}"; do
    entry_norm="$(_normalize_path "$entry")"
    [ -z "$entry_norm" ] && continue

    case "$entry_norm" in
      */\*)
        base="${entry_norm%/*}"
        base="$(_normalize_path "$base")"
        if [ "$path" = "$base" ] || [[ "$path" == "$base/"* ]]; then
          return 0
        fi
        ;;
      *)
        if [ "$path" = "$entry_norm" ] || [[ "$path" == "$entry_norm/"* ]]; then
          return 0
        fi
        ;;
    esac
  done

  return 1
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
    _safety_error "$MDOCTOR_SAFE_ERR_INVALID_TARGET" "$raw_path" "invalid deletion target: empty path"
    return "$MDOCTOR_SAFE_ERR_INVALID_TARGET"
  fi

  case "$path" in
    /*) ;;
    *)
      _safety_error "$MDOCTOR_SAFE_ERR_INVALID_TARGET" "$path" "invalid deletion target: must be absolute"
      return "$MDOCTOR_SAFE_ERR_INVALID_TARGET"
      ;;
  esac

  if [[ "$path" =~ (^|/)\.\.(/|$) ]]; then
    _safety_error "$MDOCTOR_SAFE_ERR_INVALID_TARGET" "$path" "invalid deletion target: traversal detected"
    return "$MDOCTOR_SAFE_ERR_INVALID_TARGET"
  fi

  if [[ "$path" == *$'\n'* ]] || [[ "$path" == *$'\r'* ]] || [[ "$path" == *$'\t'* ]]; then
    _safety_error "$MDOCTOR_SAFE_ERR_INVALID_TARGET" "$path" "invalid deletion target: control characters"
    return "$MDOCTOR_SAFE_ERR_INVALID_TARGET"
  fi

  if is_protected_deletion_path "$path"; then
    _safety_error "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" "$path" "blocked protected deletion target"
    return "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET"
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

  if is_whitelisted_cleanup_path "$path"; then
    _safety_log "[SAFE][SKIP:WHITELIST] $path"
    if declare -f op_record >/dev/null 2>&1; then
      op_record "SKIP_WHITELIST" "$path"
    fi
    return 0
  fi

  if [ -L "$path" ] && [ "$allow_symlink" != true ]; then
    _safety_error "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" "$path" "blocked symlink deletion without explicit allow"
    return "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED"
  fi

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi

  if [ "${DRY_RUN:-true}" = true ]; then
    _safety_log "[DRY RUN][SAFE_REMOVE] $path"
    if declare -f op_record >/dev/null 2>&1; then
      op_record "DRY_RUN_REMOVE" "$path"
    fi
    return 0
  fi

  local rm_out=""
  local rm_rc=0
  rm_out=$(rm -rf -- "$path" 2>&1) || rm_rc=$?

  if [ "$rm_rc" -ne 0 ]; then
    local mapped="$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE"

    case "$rm_out" in
      *"Read-only file system"*|*"Operation not permitted"*)
        mapped="$MDOCTOR_SAFE_ERR_SIP_READONLY"
        ;;
      *"Permission denied"*)
        mapped="$MDOCTOR_SAFE_ERR_PERMISSION_DENIED"
        ;;
    esac

    _safety_error "$mapped" "$path" "failed to remove target: $path${rm_out:+ | ${rm_out}}"
    return "$mapped"
  fi

  _safety_log "[SAFE][REMOVED] $path"
  if declare -f op_record >/dev/null 2>&1; then
    op_record "REMOVE" "$path"
  fi
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

  local matches_file
  local err_file
  matches_file=$(mktemp "${TMPDIR:-/tmp}/mdoctor-safe-find.matches.XXXXXX")
  err_file=$(mktemp "${TMPDIR:-/tmp}/mdoctor-safe-find.err.XXXXXX")

  if ! "${find_cmd[@]}" >"$matches_file" 2>"$err_file"; then
    local find_err
    find_err=$(tr '\n' ' ' <"$err_file" 2>/dev/null || true)
    rm -f "$matches_file" "$err_file"
    _safety_error "$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE" "$base_dir" "failed to enumerate deletion candidates: ${find_err:-find error}"
    return "$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE"
  fi

  local count=0
  local rc=0
  local match=""

  while IFS= read -r -d '' match; do
    count=$((count + 1))
    safe_remove "$match" --allow-symlink || rc=$?
  done <"$matches_file"

  rm -f "$matches_file" "$err_file"

  if [ "$count" -eq 0 ]; then
    _safety_log "[SAFE] no deletion candidates in: $base_dir"
    if declare -f op_record >/dev/null 2>&1; then
      op_record "NO_DELETE_CANDIDATE" "$base_dir"
    fi
  fi

  return "$rc"
}
