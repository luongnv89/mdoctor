#!/usr/bin/env bash
#
# lib/safety.sh
# Centralized deletion safety primitives for cleanup operations
#

# safe_remove needs is_dry_run (Task 1.6). Engines load lib/common.sh
# first, but standalone sourcing may not — pull it in.
if ! declare -f is_dry_run >/dev/null 2>&1; then
  _MDOCTOR_SAFETY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
  # shellcheck source=/dev/null
  source "${_MDOCTOR_SAFETY_DIR}/common.sh"
  unset _MDOCTOR_SAFETY_DIR
fi

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
# shellcheck disable=SC2034 # public API: referenced by name from external callers, not within this repo
MDOCTOR_SAFE_ERR_INVALID_PATH="$MDOCTOR_SAFE_ERR_INVALID_TARGET"
# shellcheck disable=SC2034 # public API: referenced by name from external callers, not within this repo
MDOCTOR_SAFE_ERR_PROTECTED_PATH="$MDOCTOR_SAFE_ERR_PROTECTED_TARGET"
# shellcheck disable=SC2034 # public API: referenced by name from external callers, not within this repo
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

  # Collapse repeated slashes: // -> / (repeat until stable; Bash 3.2-safe)
  while [[ "$path" == *"//"* ]]; do
    path="${path//\/\//\/}"
  done

  # Collapse /./ segments: /a/./b -> /a/b
  while [[ "$path" == *"/./"* ]]; do
    path="${path//\/.\//\/}"
  done

  # Keep / intact; trim trailing slash and trailing /. otherwise
  if [ "$path" != "/" ]; then
    while [ "${path%/}" != "$path" ]; do
      path="${path%/}"
    done
    if [ "${path%/.}" != "$path" ]; then
      path="${path%/.}"
      [ -z "$path" ] && path="/"
    fi
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

# Positive allowlist of deletion roots (Task 0.4). Every filesystem
# deletion must sit under one of these known cache/temp roots; the
# denylist in is_protected_deletion_path remains as a backstop. The same
# list is documented in docs/SAFETY.md ("Allowed deletion roots").
# Prints one root per line, $HOME-resolved at call time so sandboxed
# test runs (overridden HOME) get matching roots.
_mdoctor_allowed_deletion_roots() {
  local home="${HOME:-}"
  [ -n "$home" ] || return 0
  printf '%s\n' \
    "${TMPDIR:-/tmp}" \
    "/tmp" \
    "/var/tmp" \
    "/var/crash" \
    "$home/.Trash" \
    "$home/.cache" \
    "$home/.npm" \
    "$home/.yarn" \
    "$home/.m2" \
    "$home/.gradle" \
    "$home/.cargo" \
    "$home/.local/share/Trash" \
    "$home/.local/share/mdoctor" \
    "$home/.local/share/apport" \
    "$home/.local/share/pnpm" \
    "$home/Library/Caches" \
    "$home/Library/Logs" \
    "$home/Library/Developer" \
    "$home/Library/Application Support/MobileSync" \
    "$home/go" \
    "$home/miniconda3" \
    "$home/anaconda3"
}

# Returns 0 when the (already normalized) path sits under an allowed root.
_is_under_allowed_root() {
  local path="${1-}"
  local root norm_root

  while IFS= read -r root; do
    [ -z "$root" ] && continue
    norm_root="$(_normalize_path "$root")"
    [ -z "$norm_root" ] && continue
    if [ "$path" = "$norm_root" ] || [[ "$path" == "$norm_root/"* ]]; then
      return 0
    fi
  done < <(_mdoctor_allowed_deletion_roots)

  # Stale node_modules cleanup (cleanups/dev_caches.sh) targets
  # "<project>/node_modules" at any depth under HOME. The basename rule
  # keeps this exception tight: only a directory literally named
  # node_modules, never its parents or siblings.
  local home_norm
  home_norm="$(_normalize_path "${HOME:-}")"
  if [ -n "$home_norm" ]; then
    case "$path" in
      "$home_norm"/*/node_modules)
        return 0
        ;;
    esac
  fi

  return 1
}

is_protected_deletion_path() {
  local path
  path="$(_normalize_path "${1-}")"

  # Fail closed: an empty or unset HOME (legal in cron, launchd, systemd
  # and containers; not caught by `set -u`) collapses every computed
  # target onto a system directory, so everything is protected.
  if [ -z "${HOME:-}" ]; then
    return 0
  fi

  # Carve-outs for legitimate module targets (Task 0.4): these sit under
  # broadly-protected parents but are allowlisted explicitly. The
  # allowlist check in validate_deletion_path still applies to them.
  # NOTE: /Library/Logs/DiagnosticReports is deliberately NOT carved out
  # (Task 0.4 acceptance): system-wide diagnostic reports are outside the
  # user-cleanup scope, so macOS crash cleanup covers the user domain only.
  case "$path" in
    /var/crash|/var/crash/*|/var/tmp|/var/tmp/*)
      return 1
      ;;
  esac

  case "$path" in
    /|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/usr/lib|/System|/private|/private/etc|/private/var|/etc|/var|/Library|/Applications)
      return 0
      ;;
    /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/usr/lib/*|/System/*|/private/etc/*|/private/var/*|/etc/*|/var/*|/Library/*)
      return 0
      ;;
  esac

  local home_norm
  home_norm="$(_normalize_path "$HOME")"
  case "$path" in
    "$home_norm"|"$home_norm/Desktop"|"$home_norm/Documents"|"$home_norm/Library"|"$home_norm/.ssh"|"$home_norm/.gnupg"|"$home_norm/.local"|"$home_norm/.local/share"|"$home_norm/.config")
      return 0
      ;;
  esac

  # Linux system-critical paths
  case "$path" in
    /boot|/boot/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*)
      return 0
      ;;
    /snap|/snap/*|/lost+found|/lib|/lib/*|/lib64|/lib64/*)
      return 0
      ;;
  esac

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

  if ! _is_under_allowed_root "$path"; then
    _safety_error "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" "$path" "deletion target is outside the allowed cache/temp roots (see docs/SAFETY.md)"
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

  # Central fail-closed predicate (Task 1.6): only rc 1 removes.
  local _dry_rc=0
  is_dry_run || _dry_rc=$?
  if [ "$_dry_rc" -ne 1 ]; then
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
