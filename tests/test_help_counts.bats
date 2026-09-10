#!/usr/bin/env bats
#
# Regression test for Task 8.4 (#78):
#   help is rendered from the registry; every user-facing count is computed
#   per type at render time and agrees across list/help/check/clean outputs.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

@test "no stale hardcoded counts survive in mdoctor" {
  count=$(grep -c '21 checks\|9 targets' "$ROOT_DIR/mdoctor" || true)
  [ "$count" -eq 0 ]
}

@test "help lives in usage_* outside parse loops; one shared flag parser" {
  grep -q '^usage_check()' "$ROOT_DIR/lib/help.sh"
  grep -q '^usage_clean()' "$ROOT_DIR/lib/help.sh"
  grep -q '^usage_fix()' "$ROOT_DIR/lib/help.sh"
  grep -q '^parse_common_args()' "$ROOT_DIR/lib/help.sh"
  for cmd in cmd_check cmd_clean cmd_fix cmd_diagnose cmd_update; do
    grep -q "parse_common_args usage_" "$ROOT_DIR/mdoctor" || fail "$cmd missing shared parser"
  done
  leftover=$(grep -c 'debug_flag' "$ROOT_DIR/mdoctor" || true)
  [ "$leftover" -eq 0 ]
}

@test "list header count equals listed check rows" {
  out=$("$ROOT_DIR/mdoctor" list 2>&1)
  header=$(printf '%s\n' "$out" | grep -o 'Check Modules ([0-9]*' | grep -o '[0-9]*')
  rows=$(printf '%s\n' "$out" | awk '/^Check Modules/{s=1;next} /^Cleanup Modules/{s=0} s&&/\[/{n++} END{print n+0}')
  [ -n "$header" ]
  [ "$header" -eq "$rows" ]
}

@test "help, check --help and clean --help counts match list" {
  list_check=$(./mdoctor list 2>&1 | grep -o 'Check Modules ([0-9]*' | grep -o '[0-9]*')
  list_cleanup=$(./mdoctor list 2>&1 | grep -o 'Cleanup Modules ([0-9]*)' | grep -o '[0-9]*')
  help_check=$(./mdoctor help 2>&1 | grep -o 'read-only, [0-9]* checks' | grep -o '[0-9]*')
  help_clean=$(./mdoctor help 2>&1 | grep -o 'by default, [0-9]* modules' | grep -o '[0-9]*')
  check_help=$(./mdoctor check --help 2>&1 | grep -o 'Check modules ([0-9]*' | grep -o '[0-9]*')
  clean_help=$(./mdoctor clean --help 2>&1 | grep -o 'Cleanup modules ([0-9]*' | grep -o '[0-9]*')
  [ "$help_check" -eq "$list_check" ]
  [ "$check_help" -eq "$list_check" ]
  [ "$help_clean" -eq "$list_cleanup" ]
  [ "$clean_help" -eq "$list_cleanup" ]
}
