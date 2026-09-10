#!/usr/bin/env bats
#
# Regression test for Task 8.5 (#79):
#   cmd_clean's nested helpers live in lib/clean_common.sh, take the module
#   list explicitly, and are directly unit-testable; cmd_clean itself is
#   argument parsing plus three dispatch branches (< 60 lines, no nesting).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

error() { echo "Error: $*" >&2; }

setup() {
  cd "$ROOT_DIR" || return 1
  export MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DEBUG=false
  BOLD=""; RESET=""
  export BOLD RESET
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  source "$ROOT_DIR/lib/help.sh"
  source "$ROOT_DIR/lib/safety.sh"
  source "$ROOT_DIR/lib/cleanup_scope.sh"
  source "$ROOT_DIR/lib/clean_common.sh"
  register_all_modules
  LIST="$(registry_names cleanup)"
  export LIST
}

@test "is_valid_cleanup_module checks membership in the passed list" {
  is_valid_cleanup_module "$LIST" trash
  is_valid_cleanup_module "$LIST" apt
  run is_valid_cleanup_module "$LIST" bogus_nope
  [ "$status" -ne 0 ]
  run is_valid_cleanup_module "$LIST" "../../tmp/x"
  [ "$status" -ne 0 ]
  run is_valid_cleanup_module "trash caches" apt
  [ "$status" -ne 0 ]
}

@test "cleanup_module_description resolves listed modules only" {
  [ -n "$(cleanup_module_description "$LIST" trash)" ]
  [ -z "$(cleanup_module_description "$LIST" bogus_nope)" ]
}

@test "select_interactive_modules picks from the passed list" {
  out=$(printf 'all\n' | select_interactive_modules "$LIST" 2>/dev/null)
  [[ "$out" == *"trash"* ]]
  [[ "$out" == *"apt"* ]]
  printf '\n' | select_interactive_modules "$LIST" >/dev/null 2>&1 || rc=$?
  [ "${rc:-0}" -eq 1 ]
  printf '999\n' | select_interactive_modules "$LIST" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

@test "run_single_cleanup_module dry-runs trash in a sandbox HOME" {
  run_single_cleanup_module "$LIST" trash false
}

@test "run_interactive_cleanup runs the picked module" {
  out=$(printf '1\n' | run_interactive_cleanup "$LIST" false 2>&1)
  rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" == *"Running cleanup module: trash"* ]]
}

@test "cmd_clean has no nested definitions and is under 60 lines" {
  start=$(grep -n '^cmd_clean()' "$ROOT_DIR/mdoctor" | cut -d: -f1)
  body=$(sed -n "${start},/^}/p" "$ROOT_DIR/mdoctor" | tail -n +2)
  nested=$(printf '%s\n' "$body" | grep -c '^[[:space:]]*[a-z_][a-z_0-9]*()' || true)
  [ "$nested" -eq 0 ]
  count=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
  [ "$count" -lt 60 ]
}
