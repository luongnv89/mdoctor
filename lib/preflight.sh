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

# _preflight_find_entries BASE [FIND ARGS...] — producer for
# preflight_find_kb: streams NUL-separated entry paths, then a final
# _MDOCTOR_FIND_RC_<n> sentinel carrying the find exit code (the rc of a
# process substitution is lost, and command substitution would drop the
# NUL separators, Task 3.6). Wraps the find in a timeout where available
# (GNU-only; macOS runs it directly). A path literally named
# "_MDOCTOR_FIND_RC_<n>" would be mistaken for the sentinel.
_preflight_find_entries() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$@" -print0 2>/dev/null
    printf '%s' "_MDOCTOR_FIND_RC_$?"
  else
    find "$@" -print0 2>/dev/null
    printf '%s' "_MDOCTOR_FIND_RC_$?"
  fi
}

# preflight_find_kb BASE [FIND ARGS...] — summed size in KB of all entries
# under BASE matching the given find arguments. Prints the total only on
# success (rc 0); distinct failure codes (Task 9.4): a missing base returns
# MDOCTOR_SIZE_ERR_NO_TARGET, a timed-out find MDOCTOR_SIZE_ERR_TIMEOUT;
# entries whose own size probe fails are skipped (the total of what was
# measurable stays a genuine measurement).
preflight_find_kb() {
  local base="${1-}"
  shift || true

  if [ -z "$base" ] || [ ! -d "$base" ]; then
    return "$MDOCTOR_SIZE_ERR_NO_TARGET"
  fi

  local total=0
  local p=""
  local sz=""
  local find_rc=0
  while IFS= read -r -d '' p; do
    case "$p" in
      _MDOCTOR_FIND_RC_*)
        find_rc="${p#_MDOCTOR_FIND_RC_}"
        ;;
      *)
        sz=""
        local sz_rc=0
        sz=$(du_size_kb "$p") || sz_rc=$?
        if [ "$sz_rc" -eq 0 ]; then
          total=$((total + ${sz:-0}))
        fi
        ;;
    esac
  done < <(_preflight_find_entries "$base" "$@")

  if [ "$find_rc" -eq 124 ]; then
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi

  printf '%s\n' "$total"
  return 0
}
