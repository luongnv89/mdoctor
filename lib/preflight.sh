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

# Guard against double-sourcing.
if [ "${_MDOCTOR_PREFLIGHT_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_PREFLIGHT_LOADED=true

# preflight_path_kb PATH — size of one path in KB, always numeric.
# Thin wrapper over du_size_kb: echoes the size (0 on failure) and
# propagates its error channel ($MDOCTOR_SIZE_ERR_*; 0 only for a genuine
# measurement). Callers capture the status and report "could not
# determine" instead of treating 0 as empty.
preflight_path_kb() {
  du_size_kb "${1-}"
}

# preflight_find_kb BASE [FIND ARGS...] — summed size in KB of all entries
# under BASE matching the given find arguments, always numeric. Echoes the
# total (0 on failure) and returns 0 only for a genuine measurement:
# NOT_DIR when BASE is missing, DENIED when BASE is unreadable or the
# find itself fails, TIMEOUT when the bounded find hits
# MDOCTOR_FIND_TIMEOUT_S. Per-entry du races (a candidate vanishing
# mid-scan) contribute 0 without tainting the whole sum.
preflight_find_kb() {
  local base="${1-}"
  shift || true

  if [ -z "$base" ] || [ ! -d "$base" ]; then
    echo 0
    return "$MDOCTOR_SIZE_ERR_NOT_DIR"
  fi
  if [ ! -r "$base" ] || [ ! -x "$base" ]; then
    echo 0
    return "$MDOCTOR_SIZE_ERR_DENIED"
  fi

  local matches_file=""
  matches_file="$(mktemp "${TMPDIR:-/tmp}/mdoctor-preflight-find.XXXXXX" 2>/dev/null)" || matches_file=""
  if [ -z "$matches_file" ]; then
    echo 0
    return 1
  fi

  local find_rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MDOCTOR_FIND_TIMEOUT_S" find "$base" "$@" -print0 >"$matches_file" 2>/dev/null || find_rc=$?
  else
    find "$base" "$@" -print0 >"$matches_file" 2>/dev/null || find_rc=$?
  fi
  if [ "$find_rc" -eq 124 ]; then
    rm -f "$matches_file"
    echo 0
    return "$MDOCTOR_SIZE_ERR_TIMEOUT"
  fi
  if [ "$find_rc" -ne 0 ]; then
    rm -f "$matches_file"
    echo 0
    return "$MDOCTOR_SIZE_ERR_DENIED"
  fi

  local total=0
  local p=""
  local sz=""
  local sz_rc=0
  while IFS= read -r -d '' p; do
    sz_rc=0
    sz=$(du_size_kb "$p") || sz_rc=$?
    if [ "$sz_rc" -ne 0 ]; then
      sz="0"
    fi
    total=$((total + ${sz:-0}))
  done <"$matches_file"
  rm -f "$matches_file"

  echo "$total"
  return 0
}
