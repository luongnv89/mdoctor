#!/usr/bin/env bash
#
# lib/preflight.sh
# Shared pre-flight size estimators (Task 8.3, part 1 of the god-module split).
# Both entry points (`mdoctor` single-module pre-flight and `cleanup.sh` full
# pre-flight) source this module so the estimate logic exists once and both
# produce byte-identical numbers for the same target set.
#
# Sourcing contract: lib/disk.sh must be sourced first (du_size_kb,
# human_readable_kb).
#


# TRUTHY_BOOTSTRAP (Task 9.5): is_truthy lives in constants.sh, the
# zero-dependency base lib. Source it before the guard so standalone
# sourcing of this file still sees the predicate.
_MDOCTOR_TRUTHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
# shellcheck source=/dev/null
source "${_MDOCTOR_TRUTHY_DIR}/constants.sh"
unset _MDOCTOR_TRUTHY_DIR

if is_truthy "${_MDOCTOR_PREFLIGHT_LOADED:-}"; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PREFLIGHT_LOADED=true

# preflight_path_kb PATH — size of one path in KB. Prints the size only on
# success (rc 0); on failure prints nothing and propagates the distinct
# MDOCTOR_SIZE_ERR_* code from du_size_kb (Task 9.4).
preflight_path_kb() {
  local kb=""
  local rc=0
  kb=$(du_size_kb "${1-}") || rc=$?
  if [ "$rc" -ne 0 ]; then
    return "$rc"
  fi
  printf '%s\n' "$kb"
}

# _preflight_find_entries BASE [FIND ARGS...] — matcher producer for
# preflight_find_kb: streams NUL-separated entry paths, then a final
# _MDOCTOR_FIND_RC_<n> sentinel carrying the find exit code (the rc of a
# process substitution is lost, and command substitution would drop the
# NUL separators, Task 3.6). Wraps the find in a timeout where available
# (GNU-only; macOS runs it directly). A path literally named
# "_MDOCTOR_FIND_RC_<n>" would be mistaken for the sentinel.
_preflight_find_entries() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  else
    find "$@" -print0 2>/dev/null
    printf '%s\0' "_MDOCTOR_FIND_RC_$?"
  fi
}

# _preflight_find_printf_ok — memoized capability probe for
# _preflight_find_size_kb. GNU find prints each entry's allocated size in
# the sizing pass itself (-printf '%k\n'); BSD find (macOS) has no
# -printf, so the sizer falls back to one batched `stat -f %b` exec pass.
# Probed once per process under the same timeout as the scan so a wedged
# find can never stall it, then memoized for the remaining call sites.
_MDOCTOR_FIND_PRINTF_OK=""
_preflight_find_printf_ok() {
  local rc=0
  if [ -n "$_MDOCTOR_FIND_PRINTF_OK" ]; then
    is_truthy "$_MDOCTOR_FIND_PRINTF_OK"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find . -maxdepth 0 -printf '%k\n' >/dev/null 2>&1 || rc=$?
  else
    find . -maxdepth 0 -printf '%k\n' >/dev/null 2>&1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    _MDOCTOR_FIND_PRINTF_OK=true
  else
    _MDOCTOR_FIND_PRINTF_OK=false
  fi
  is_truthy "$_MDOCTOR_FIND_PRINTF_OK"
}

# _preflight_find_size_kb PATH... — the sizing pass (Task 11.1): one find
# invocation over the already-resolved match set, never a du per entry.
# GNU find emits each entry's %k — allocated 1K blocks, the same figure
# du_size_kb reported per entry; for a directory match the traversal
# sums the whole subtree exactly like a recursive du did. BSD find
# (macOS) has no -printf, so it batches `stat -f %b` (allocated 512-byte
# blocks) over the set and awk applies the same per-entry round-up to KB
# that du uses.
# Prints the KB total on rc 0; a pass that measured nothing propagates
# the find exit code and a timed-out pass the timeout code, while a
# partially measured stream still prints its (genuine) total — entries
# whose own probe failed were always skipped.
_preflight_find_size_kb() {
  local stream="" rc=0
  if _preflight_find_printf_ok; then
    if command -v timeout >/dev/null 2>&1; then
      stream=$(timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -printf '%k\n' 2>/dev/null) || rc=$?
    else
      stream=$(find "$@" -printf '%k\n' 2>/dev/null) || rc=$?
    fi
    if [ "$rc" -eq 124 ]; then
      return "$MDOCTOR_SIZE_ERR_TIMEOUT"
    fi
    if [ -z "$stream" ]; then
      [ "$rc" -eq 0 ] || return "$rc"
      printf '0\n'
      return 0
    fi
    printf '%s\n' "$stream" | awk '{ s += $1 } END { print s+0 }'
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    stream=$(timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -exec stat -f %b {} + 2>/dev/null) || rc=$?
  else
    stream=$(find "$@" -exec stat -f %b {} + 2>/dev/null) || rc=$?
  fi
  if [ "$rc" -eq 124 ]; then
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi
  if [ -z "$stream" ]; then
    [ "$rc" -eq 0 ] || return "$rc"
    printf '0\n'
    return 0
  fi
  printf '%s\n' "$stream" | awk 'NF { s += int(($1+1)/2) } END { print s+0 }'
  return 0
}

# preflight_find_kb BASE [FIND ARGS...] — summed size in KB of all entries
# under BASE matching the given find arguments; a matched directory
# contributes its whole subtree, exactly as the retired per-entry du
# loop measured it. Prints the total only on success (rc 0); distinct
# failure codes (Task 9.4): a missing base returns
# MDOCTOR_SIZE_ERR_NO_TARGET, an untraversable one MDOCTOR_SIZE_ERR_DENIED,
# a timed-out find MDOCTOR_SIZE_ERR_TIMEOUT; a partially measured match
# set keeps its (genuine) total.
preflight_find_kb() {
  local base="${1-}"
  shift || true

  if [ -z "$base" ] || [ ! -d "$base" ]; then
    return "$MDOCTOR_SIZE_ERR_NO_TARGET"
  fi
  if [ ! -r "$base" ] || [ ! -x "$base" ]; then
    return "$MDOCTOR_SIZE_ERR_DENIED"
  fi

  # Pass 1 (Task 11.1): resolve the match set once — NUL-separated, so
  # newline-bearing paths stay safe — keeping the find exit code via the
  # _MDOCTOR_FIND_RC_<n> sentinel.
  local -a matches=()
  local p=""
  local find_rc=0
  while IFS= read -r -d '' p; do
    case "$p" in
      _MDOCTOR_FIND_RC_*)
        find_rc="${p#_MDOCTOR_FIND_RC_}"
        ;;
      *)
        matches+=("$p")
        ;;
    esac
  done < <(_preflight_find_entries "$base" "$@")

  case "$find_rc" in
    0) ;;
    124) return "$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
    1) return "$MDOCTOR_SIZE_ERR_DENIED" ;;
    *) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
  esac

  local n="${#matches[@]}"
  if [ "$n" -eq 0 ]; then
    printf '0\n'
    return 0
  fi

  # Pass 2: one sizing traversal over the match set — the per-entry
  # du + awk spawn that made this 210x slower is gone (F-PERF-004).
  # Chunked so a very large match set can never overflow exec argv.
  local total=0
  local i=0
  local chunk_kb=""
  local chunk_rc=0
  while [ "$i" -lt "$n" ]; do
    chunk_rc=0
    chunk_kb=$(_preflight_find_size_kb "${matches[@]:$i:$MDOCTOR_FIND_ARGV_CHUNK}") || chunk_rc=$?
    case "$chunk_rc" in
      0) ;;
      124) return "$MDOCTOR_SIZE_ERR_TIMEOUT" ;;
      1) return "$MDOCTOR_SIZE_ERR_DENIED" ;;
      *) return "$MDOCTOR_SIZE_ERR_FAILED" ;;
    esac
    total=$((total + ${chunk_kb:-0}))
    i=$((i + MDOCTOR_FIND_ARGV_CHUNK))
  done

  printf '%s\n' "$total"
  return 0
}
