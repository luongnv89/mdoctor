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
preflight_path_kb() {
  du_size_kb "${1-}"
}

# preflight_find_kb BASE [FIND ARGS...] — summed size in KB of all entries
# under BASE matching the given find arguments, always numeric.
preflight_find_kb() {
  local base="${1-}"
  shift || true

  if [ -z "$base" ] || [ ! -d "$base" ]; then
    echo 0
    return 0
  fi

  local total=0
  local p=""
  while IFS= read -r -d '' p; do
    local sz=""
    sz=$(du_size_kb "$p")
    total=$((total + ${sz:-0}))
  done < <(find "$base" "$@" -print0 2>/dev/null)

  echo "$total"
}
