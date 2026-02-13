#!/usr/bin/env bash
#
# lib/metadata.sh
# Module metadata registry using parallel indexed arrays (Bash 3.2 compatible)
#

########################################
# MODULE REGISTRY
########################################

# Parallel indexed arrays — no associative arrays (Bash 3.2)
_MOD_TYPES=()    # check, cleanup, fix
_MOD_NAMES=()    # module name (e.g., "system", "trash", "homebrew")
_MOD_CATS=()     # Hardware, Software, System
_MOD_RISKS=()    # SAFE, LOW, MED, HIGH
_MOD_DESCS=()    # human-readable description
_MOD_FUNCS=()    # function name to call
_MOD_COUNT=0

# register_module TYPE NAME CATEGORY RISK FUNCTION DESCRIPTION
register_module() {
  local type="$1"
  local name="$2"
  local category="$3"
  local risk="$4"
  local func="$5"
  local desc="$6"

  _MOD_TYPES[_MOD_COUNT]="$type"
  _MOD_NAMES[_MOD_COUNT]="$name"
  _MOD_CATS[_MOD_COUNT]="$category"
  _MOD_RISKS[_MOD_COUNT]="$risk"
  _MOD_FUNCS[_MOD_COUNT]="$func"
  _MOD_DESCS[_MOD_COUNT]="$desc"
  _MOD_COUNT=$((_MOD_COUNT + 1))
}

# get_module_index NAME TYPE → prints index or returns 1
get_module_index() {
  local name="$1"
  local type="${2:-}"
  local i=0
  while (( i < _MOD_COUNT )); do
    if [ "${_MOD_NAMES[$i]}" = "$name" ]; then
      if [ -z "$type" ] || [ "${_MOD_TYPES[$i]}" = "$type" ]; then
        echo "$i"
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

# get_module_func NAME TYPE → prints function name
get_module_func() {
  local idx
  if idx=$(get_module_index "$1" "${2:-}"); then
    echo "${_MOD_FUNCS[$idx]}"
  fi
}

# get_module_risk NAME TYPE → prints risk level
get_module_risk() {
  local idx
  if idx=$(get_module_index "$1" "${2:-}"); then
    echo "${_MOD_RISKS[$idx]}"
  fi
}

# risk_badge RISK → prints colored badge string
risk_badge() {
  local risk="$1"
  case "$risk" in
    SAFE) echo "[SAFE]" ;;
    LOW)  echo "[LOW]" ;;
    MED)  echo "[MED]" ;;
    HIGH) echo "[HIGH]" ;;
    *)    echo "[$risk]" ;;
  esac
}

# list_modules [TYPE] → prints formatted table of modules
list_modules() {
  local filter_type="${1:-}"
  local i=0
  while (( i < _MOD_COUNT )); do
    if [ -z "$filter_type" ] || [ "${_MOD_TYPES[$i]}" = "$filter_type" ]; then
      printf "  %-8s %-14s %-10s %-6s %s\n" \
        "${_MOD_TYPES[$i]}" \
        "${_MOD_NAMES[$i]}" \
        "${_MOD_CATS[$i]}" \
        "$(risk_badge "${_MOD_RISKS[$i]}")" \
        "${_MOD_DESCS[$i]}"
    fi
    i=$((i + 1))
  done
}

# list_modules_by_category TYPE → prints modules grouped by category
list_modules_by_category() {
  local filter_type="${1:-}"
  local cat
  local i

  # Print Hardware first, then System, then Software
  for cat in Hardware System Software; do
    local found=0
    i=0
    while (( i < _MOD_COUNT )); do
      if [ "${_MOD_CATS[$i]}" = "$cat" ]; then
        if [ -z "$filter_type" ] || [ "${_MOD_TYPES[$i]}" = "$filter_type" ]; then
          if [ "$found" -eq 0 ]; then
            echo "  ${cat}:"
            found=1
          fi
          printf "    %-14s %-6s %s\n" \
            "${_MOD_NAMES[$i]}" \
            "$(risk_badge "${_MOD_RISKS[$i]}")" \
            "${_MOD_DESCS[$i]}"
        fi
      fi
      i=$((i + 1))
    done
  done
}
