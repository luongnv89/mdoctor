#!/usr/bin/env bash
#
# lib/json.sh
# Pure-Bash JSON output support (no jq dependency)
#

########################################
# JSON STATE
########################################

JSON_ENABLED="${JSON_ENABLED:-false}"
_JSON_CHECKS=()     # accumulated check result JSON fragments
_JSON_ACTIONS=()    # accumulated action strings
_JSON_MODULE=""     # module currently executing (set by engines, read by status helpers)
_JSON_CATEGORY=""
_JSON_RISK=""

# json_set_context MODULE CATEGORY RISK
# Records which check module subsequent status results belong to. Engines
# call this before each check so the status_* helpers in lib/common.sh can
# attribute results; without it the "checks" array stays permanently empty.
json_set_context() {
  _JSON_MODULE="${1:-}"
  _JSON_CATEGORY="${2:-}"
  _JSON_RISK="${3:-}"
}

########################################
# JSON HELPERS
########################################

# json_escape STRING → prints JSON-safe string (RFC 8259 §7: backslash,
# double quote, and every control char U+0000–U+001F is escaped; U+0000
# needs no handling because Bash strings can never contain NUL).
# Per-character scan (ordinal via printf "'c", short forms + \u00XX):
# pattern-substitution on raw control bytes and `printf %b '\0NNN'`
# round-trips vary across Bash builds (Apple Bash 3.2 on macOS left a
# raw control in the document, breaking `mdoctor check --json` there),
# so no control byte is ever placed in a pattern or rebuilt from octal.
# Bash 3.2 compatible (substring expansion, printf -v, += only).
json_escape() {
  local str="$1"
  local out="" i ch code esc
  i=0
  while (( i < ${#str} )); do
    ch="${str:$i:1}"
    printf -v code '%d' "'$ch"
    case "$code" in
      92) out+='\\' ;;       # backslash
      34) out+='\"' ;;       # double quote
      8)  out+='\b' ;;       # backspace (U+0008)
      9)  out+='\t' ;;       # tab (U+0009)
      10) out+='\n' ;;       # newline (U+000A)
      12) out+='\f' ;;       # form feed (U+000C)
      13) out+='\r' ;;       # carriage return (U+000D)
      *)
        if (( code < 32 )); then
          printf -v esc '\\u00%02x' "$code"
          out+="$esc"
        else
          out+="$ch"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# json_add_check MODULE CATEGORY RISK STATUS MESSAGE
# Accumulates a check result entry
json_add_check() {
  local module="$1"
  local category="$2"
  local risk="$3"
  local status="$4"
  local message="$5"

  local esc_module esc_cat esc_risk esc_status esc_msg
  esc_module="$(json_escape "$module")"
  esc_cat="$(json_escape "$category")"
  esc_risk="$(json_escape "$risk")"
  esc_status="$(json_escape "$status")"
  esc_msg="$(json_escape "$message")"

  _JSON_CHECKS+=("{\"module\":\"${esc_module}\",\"category\":\"${esc_cat}\",\"risk\":\"${esc_risk}\",\"status\":\"${esc_status}\",\"message\":\"${esc_msg}\"}")
}

# json_add_action MESSAGE
json_add_action() {
  local esc
  esc="$(json_escape "$1")"
  _JSON_ACTIONS+=("\"${esc}\"")
}

# json_build_output SCORE RATING WARN_COUNT FAIL_COUNT
# Prints the complete JSON document to stdout
json_build_output() {
  local score="$1"
  local rating="$2"
  local warnings="$3"
  local failures="$4"

  local esc_rating
  esc_rating="$(json_escape "$rating")"

  printf '{\n'
  # Task 5.4: MDOCTOR_VERSION is the single source of truth (set by the
  # `mdoctor` dispatcher). No literal fallback lives here: an unset
  # variable emits null rather than silently reporting a fabricated,
  # potentially stale version.
  if [ -n "${MDOCTOR_VERSION:-}" ]; then
    printf '  "version": "%s",\n' "$(json_escape "$MDOCTOR_VERSION")"
  else
    printf '  "version": null,\n'
  fi
  printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "hostname": "%s",\n' "$(json_escape "$(hostname)")"
  printf '  "score": %d,\n' "$score"
  printf '  "rating": "%s",\n' "$esc_rating"
  printf '  "warnings": %d,\n' "$warnings"
  printf '  "failures": %d,\n' "$failures"

  # Actions array
  printf '  "actions": ['
  local i=0
  local n=${#_JSON_ACTIONS[@]}
  while (( i < n )); do
    if (( i > 0 )); then
      printf ','
    fi
    printf '\n    %s' "${_JSON_ACTIONS[$i]}"
    i=$((i + 1))
  done
  if (( n > 0 )); then
    printf '\n  '
  fi
  printf '],\n'

  # Checks array
  printf '  "checks": ['
  i=0
  n=${#_JSON_CHECKS[@]}
  while (( i < n )); do
    if (( i > 0 )); then
      printf ','
    fi
    printf '\n    %s' "${_JSON_CHECKS[$i]}"
    i=$((i + 1))
  done
  if (( n > 0 )); then
    printf '\n  '
  fi
  printf ']\n'

  printf '}\n'
}
