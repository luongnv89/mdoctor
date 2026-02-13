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

########################################
# JSON HELPERS
########################################

# json_escape STRING → prints JSON-safe string (handles \, ", newlines, tabs)
json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"       # backslash
  str="${str//\"/\\\"}"       # double quote
  str="${str//$'\n'/\\n}"     # newline
  str="${str//$'\r'/\\r}"     # carriage return
  str="${str//$'\t'/\\t}"     # tab
  echo "$str"
}

# json_add_check MODULE CATEGORY RISK STATUS MESSAGE
# Accumulates a check result entry
json_add_check() {
  local module="$1"
  local category="$2"
  local risk="$3"
  local status="$4"
  local message="$5"

  local esc_module esc_cat esc_msg
  esc_module="$(json_escape "$module")"
  esc_cat="$(json_escape "$category")"
  esc_msg="$(json_escape "$message")"

  _JSON_CHECKS+=("{\"module\":\"${esc_module}\",\"category\":\"${esc_cat}\",\"risk\":\"${risk}\",\"status\":\"${status}\",\"message\":\"${esc_msg}\"}")
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
  printf '  "version": "%s",\n' "$(json_escape "${MDOCTOR_VERSION:-2.0.0}")"
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
