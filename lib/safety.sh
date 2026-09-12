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
  source "${_MDOCTOR_SAFETY_DIR}/constants.sh"
  unset _MDOCTOR_SAFETY_DIR
fi

# -----------------------------------------------------------------------------
# Error taxonomy (destructive operations)
# -----------------------------------------------------------------------------
MDOCTOR_SAFE_ERR_INVALID_TARGET=21
MDOCTOR_SAFE_ERR_PROTECTED_TARGET=22
MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED=23
MDOCTOR_SAFE_ERR_PERMISSION_DENIED=24
MDOCTOR_SAFE_ERR_SIP_OR_READONLY=25
MDOCTOR_SAFE_ERR_RUNTIME_FAILURE=26

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
  # Driven by the named error constants above (Task 8.7), never bare numbers.
  case "$code" in
    "$MDOCTOR_SAFE_ERR_INVALID_TARGET") echo "INVALID_TARGET" ;;
    "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET") echo "PROTECTED_TARGET" ;;
    "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED") echo "SYMLINK_BLOCKED" ;;
    "$MDOCTOR_SAFE_ERR_PERMISSION_DENIED") echo "PERMISSION_DENIED" ;;
    "$MDOCTOR_SAFE_ERR_SIP_OR_READONLY") echo "SIP_OR_READONLY" ;;
    "$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE") echo "RUNTIME_FAILURE" ;;
    *)  echo "UNKNOWN" ;;
  esac
}

# handle_cleanup_rc RC — Task 9.3 case distinguishing expected skips from
# real failures. Prints the mapped code (always returns 0, so callers under
# `set -e` can write rc="$(handle_cleanup_rc "$rc")"). In dry-run nothing
# is attempted, so every policy block maps to 0 (reported where it happens);
# in force mode failures propagate unchanged.
handle_cleanup_rc() {
  local rc="${1:-0}"
  if [ "$rc" -eq 0 ]; then
    echo 0
    return 0
  fi
  local _dry_rc=0
  is_dry_run || _dry_rc=$?
  if [ "$_dry_rc" -ne 1 ]; then
    echo 0
    return 0
  fi
  echo "$rc"
  return 0
}

safety_error_hint() {
  local code="${1:-0}"
  local path="${2:-target}"

  case "$code" in
    "$MDOCTOR_SAFE_ERR_INVALID_TARGET")
      echo "Use an absolute, non-traversal path. Re-check computed target: ${path}"
      ;;
    "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET")
      echo "Target is protected by safety policy. Choose a narrower cache/temp path instead: ${path}"
      ;;
    "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED")
      echo "Symlink deletion is blocked by default. Use explicit symlink-allow flow only when audited: ${path}"
      ;;
    "$MDOCTOR_SAFE_ERR_PERMISSION_DENIED")
      echo "Permission denied. Check ownership/permissions, Full Disk Access, or sudo policy for: ${path}"
      ;;
    "$MDOCTOR_SAFE_ERR_SIP_OR_READONLY")
      echo "Likely SIP/read-only restriction. Avoid protected/system paths or run from writable scope: ${path}"
      ;;
    "$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE")
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

# _normalize_path PATH [OUTVAR] — collapse //, /./, trailing / and /.
# Issue #99: with OUTVAR the result is assigned in place via printf -v
# (pure parameter expansion, no command-substitution subshell — hot path
# inside safe_remove). Called with one argument it still prints, kept for
# install.sh/uninstall.sh cold-path callers. OUTVAR must be caller-scoped
# and must not collide with the _np_* locals below.
_normalize_path() {
  local _np_path="${1-}"
  local _np_out="${2-}"

  if [ -z "$_np_path" ]; then
    if [ -n "$_np_out" ]; then
      printf -v "$_np_out" '%s' ""
    else
      echo ""
    fi
    return 0
  fi

  # Collapse repeated slashes: // -> / (repeat until stable; Bash 3.2-safe)
  while [[ "$_np_path" == *"//"* ]]; do
    _np_path="${_np_path//\/\//\/}"
  done

  # Collapse /./ segments: /a/./b -> /a/b
  while [[ "$_np_path" == *"/./"* ]]; do
    _np_path="${_np_path//\/.\//\/}"
  done

  # Keep / intact; trim trailing slash and trailing /. otherwise
  if [ "$_np_path" != "/" ]; then
    while [ "${_np_path%/}" != "$_np_path" ]; do
      _np_path="${_np_path%/}"
    done
    if [ "${_np_path%/.}" != "$_np_path" ]; then
      _np_path="${_np_path%/.}"
      [ -z "$_np_path" ] && _np_path="/"
    fi
  fi

  if [ -n "$_np_out" ]; then
    printf -v "$_np_out" '%s' "$_np_path"
  else
    echo "$_np_path"
  fi
}

ensure_cleanup_whitelist_file() {
  local file="$MDOCTOR_CLEANUP_WHITELIST_FILE"
  local dir
  dir="$(dirname "$file")"

  mkdir -p "$dir"
  # Task 3.4: state is private (0700 dirs, 0600 files).
  chmod 700 "$dir"
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
    chmod 600 "$file"
  fi
}

load_cleanup_whitelist() {
  if is_truthy "$_MDOCTOR_WHITELIST_LOADED"; then
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

# Public reload entry point: force a re-read of the whitelist file.
# Tests and long-lived shells use this instead of poking the private
# _MDOCTOR_WHITELIST_LOADED flag (renaming-safe surface).
reload_cleanup_whitelist() {
  _MDOCTOR_WHITELIST_LOADED=false
  load_cleanup_whitelist
}

is_whitelisted_cleanup_path() {
  # Empty input was the original early-out (no whitelist-file side
  # effects); normalization maps empty to empty, so test the raw arg.
  [ -z "${1-}" ] && return 1

  load_cleanup_whitelist

  # Empty whitelist (the common case) can never match — skip the
  # normalization and the entry loop entirely (issue #99).
  if [ "${#_MDOCTOR_WHITELIST[@]}" -eq 0 ]; then
    return 1
  fi

  local path
  _normalize_path "${1-}" path

  [ -z "$path" ] && return 1

  local entry=""
  local entry_norm=""
  local base=""
  for entry in "${_MDOCTOR_WHITELIST[@]+"${_MDOCTOR_WHITELIST[@]}"}"; do
    _normalize_path "$entry" entry_norm
    [ -z "$entry_norm" ] && continue

    case "$entry_norm" in
      */\*)
        base="${entry_norm%/*}"
        _normalize_path "$base" base
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
# The list assigns the _MDOCTOR_ALLOWED_ROOTS global, $HOME-resolved at
# call time so sandboxed test runs (overridden HOME) get matching roots;
# the printer wrapper keeps the line-per-root surface for callers/tests.
_mdoctor_allowed_deletion_roots_list() {
  local home="${HOME:-}"
  _MDOCTOR_ALLOWED_ROOTS=()
  [ -n "$home" ] || return 0
  _MDOCTOR_ALLOWED_ROOTS=(
    "${TMPDIR:-/tmp}"
    "/tmp"
    "/var/tmp"
    "/var/crash"
    "$home/.Trash"
    "$home/.cache"
    "$home/.npm"
    "$home/.yarn"
    "$home/.m2"
    "$home/.gradle"
    "$home/.cargo"
    "$home/.local/share/Trash"
    "$home/.local/share/mdoctor"
    "$home/.local/share/apport"
    "$home/.local/share/pnpm"
    "$home/Library/Caches"
    "$home/Library/Logs"
    "$home/Library/Developer"
    "$home/Library/Application Support/MobileSync"
    "$home/go"
    "$home/miniconda3"
    "$home/anaconda3"
  )
}

_mdoctor_allowed_deletion_roots() {
  _mdoctor_allowed_deletion_roots_list
  if [ "${#_MDOCTOR_ALLOWED_ROOTS[@]}" -gt 0 ]; then
    printf '%s\n' "${_MDOCTOR_ALLOWED_ROOTS[@]}"
  fi
}

# Returns 0 when the (already normalized) path sits under an allowed root.
_is_under_allowed_root() {
  local path="${1-}"
  local root norm_root

  # Array iteration instead of a process-substitution pipeline — one less
  # subshell per safe_remove call (issue #99).
  _mdoctor_allowed_deletion_roots_list
  for root in "${_MDOCTOR_ALLOWED_ROOTS[@]+"${_MDOCTOR_ALLOWED_ROOTS[@]}"}"; do
    [ -z "$root" ] && continue
    _normalize_path "$root" norm_root
    [ -z "$norm_root" ] && continue
    if [ "$path" = "$norm_root" ] || [[ "$path" == "$norm_root/"* ]]; then
      return 0
    fi
  done

  # Stale node_modules cleanup (cleanups/dev_caches.sh) targets
  # "<project>/node_modules" at any depth under HOME. The basename rule
  # keeps this exception tight: only a directory literally named
  # node_modules, never its parents or siblings.
  local home_norm
  _normalize_path "${HOME:-}" home_norm
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
  _normalize_path "${1-}" path

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
  _normalize_path "$HOME" home_norm
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

# validate_deletion_path PATH [CANON_OUT] — run every policy check against
# the canonical target. With CANON_OUT, the canonical (normalized) path
# computed mid-validation is assigned to that caller-scoped variable on
# success, so safe_remove/safe_remove_children reuse it instead of paying
# a second realpath fork per file (issue #99). CANON_OUT must not collide
# with the locals below.
validate_deletion_path() {
  local raw_path="${1-}"
  local _vd_canon_out="${2-}"
  local path
  _normalize_path "$raw_path" path

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

  # Task 3.2: canonicalize first (resolving symlinks, /./ and //), then
  # run every policy check against the canonical path — validation and
  # deletion can never disagree on what the target is. Traversal is
  # rejected above, before resolution could hide it.
  _canonical_path "$path" path
  _normalize_path "$path" path

  if is_protected_deletion_path "$path"; then
    _safety_error "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" "$path" "blocked protected deletion target"
    return "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET"
  fi

  if ! _is_under_allowed_root "$path"; then
    _safety_error "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" "$path" "deletion target is outside the allowed cache/temp roots (see docs/SAFETY.md)"
    return "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET"
  fi

  if [ -n "$_vd_canon_out" ]; then
    printf -v "$_vd_canon_out" '%s' "$path"
  fi
  return 0
}

safe_remove() {
  local path="${1-}"
  local allow_symlink=false

  if [ "${2-}" = "--allow-symlink" ]; then
    allow_symlink=true
  fi

  local canon_path=""
  validate_deletion_path "$path" canon_path || return $?

  if is_whitelisted_cleanup_path "$path"; then
    _safety_log "[SAFE][SKIP:WHITELIST] $path"
    if declare -f op_record >/dev/null 2>&1; then
      op_record "SKIP_WHITELIST" "$path"
    fi
    return 0
  fi

  if [ -L "$path" ] && ! is_truthy "$allow_symlink"; then
    _safety_error "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" "$path" "blocked symlink deletion without explicit allow"
    return "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED"
  fi

  # Task 3.2: operate on the canonical path so validation and deletion
  # agree — except for the symlink itself: rm on a link removes the LINK,
  # so resolving first would redirect deletion onto the TARGET. The
  # canonical path validated above is reused verbatim (issue #99) — same
  # input, same realpath result, and provably the path that was checked.
  if [ ! -L "$path" ] && [ -n "$canon_path" ]; then
    path="$canon_path"
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
        mapped="$MDOCTOR_SAFE_ERR_SIP_OR_READONLY"
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

# _mdoctor_path_link_free PATH — true only when PATH is absolute, already
# normalized (no //, /./ or .. segment) AND no component is a symlink.
# Only then is realpath's resolution provably the input string itself, so
# the realpath exec can be skipped on the overwhelmingly common path
# (issue #99). Any doubt falls back to the real exec below.
_mdoctor_path_link_free() {
  local rest="${1-}"
  local next
  case "$rest" in
    /*) ;;                                          # absolute only
    *) return 1 ;;
  esac
  case "$rest" in
    *//*|*/./*|*/../*|*/.|*/..|../*|..) return 1 ;; # not normalized
  esac
  while [ "$rest" != "/" ] && [ -n "$rest" ]; do
    if [ -L "$rest" ]; then
      return 1
    fi
    next="${rest%/*}"
    # Defensive stop for inputs without a further slash component.
    [ "$next" = "$rest" ] && break
    rest="$next"
  done
  return 0
}

# _canonical_path PATH [OUTVAR] — resolve symlinks / . / .. to a canonical
# absolute path (Task 3.1/3.2). Prefers realpath, falls back to
# readlink -f, then to the (normalized) input when neither can resolve
# (e.g. missing path). With OUTVAR the result is assigned in place; with
# one argument it prints (kept for external callers).
_canonical_path() {
  local _cp_in="${1-}"
  local _cp_out="${2-}"
  local _cp_res

  if [ -z "$_cp_in" ]; then
    _cp_res=""
  elif _mdoctor_path_link_free "$_cp_in"; then
    # No symlink component: resolution is the identity on an already
    # normalized path — same answer realpath would print, no exec.
    _cp_res="$_cp_in"
  elif command -v realpath >/dev/null 2>&1; then
    _cp_res="$(realpath "$_cp_in" 2>/dev/null)" || _cp_res=""
    [ -n "$_cp_res" ] || _cp_res="$_cp_in"
  elif _cp_res="$(readlink -f "$_cp_in" 2>/dev/null)" && [ -n "$_cp_res" ]; then
    :
  else
    _cp_res="$_cp_in"
  fi

  if [ -n "$_cp_out" ]; then
    printf -v "$_cp_out" '%s' "$_cp_res"
  else
    printf '%s' "$_cp_res"
  fi
}

safe_remove_children() {
  local dir="${1-}"
  local allow_symlink=false

  if [ "${2-}" = "--allow-symlink" ]; then
    allow_symlink=true
  fi

  # Task 3.1: a symlinked directory argument is rejected BEFORE any glob
  # expansion — otherwise "$dir"/* would enumerate (and delete) the
  # link TARGET's children. Explicit --allow-symlink opts in.
  if [ -L "$dir" ] && ! is_truthy "$allow_symlink"; then
    _safety_error "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" "$dir" "blocked symlinked directory argument without explicit allow"
    return "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED"
  fi

  # Task 3.1: canonicalize (resolving any remaining indirection) and
  # re-validate the canonical result before touching anything. Validation
  # already resolved it — take the exported canonical path (issue #99).
  local canon_dir=""
  validate_deletion_path "$dir" canon_dir || return $?
  if [ "$canon_dir" != "$dir" ]; then
    validate_deletion_path "$canon_dir" || return $?
    dir="$canon_dir"
  fi

  if [ ! -d "$dir" ]; then
    return 0
  fi

  local rc=0
  local item
  for item in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$item" ] || [ -L "$item" ] || continue
    if is_truthy "$allow_symlink"; then
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

  # Task 3.2: symlink allowance is an explicit opt-in flag in $1 position
  # (before the find args), defaulting to blocked. Previously every match
  # was removed with --allow-symlink unconditionally.
  local allow_symlink=false
  if [ "${1-}" = "--allow-symlink" ]; then
    allow_symlink=true
    shift || true
  fi

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

  # Loop-invariant: evaluate the symlink allowance once, not per file.
  local _allow_symlink_rc=0
  is_truthy "$allow_symlink" || _allow_symlink_rc=$?

  while IFS= read -r -d '' match; do
    count=$((count + 1))
    if [ "$_allow_symlink_rc" -eq 0 ]; then
      safe_remove "$match" --allow-symlink || rc=$?
    else
      safe_remove "$match" || rc=$?
    fi
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
