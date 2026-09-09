#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

# trash_menu_index (issue #74, F-TEST-015): derive the trash module's menu
# number from the rendered interactive menu instead of hardcoding position
# 1. The menu order follows the cleanup_modules array in `mdoctor`, so a
# hardcoded `1` silently repoints a force cleanup at a different module if
# that array is ever reordered. Prints the 1-based index on stdout.
trash_menu_index() {
  local menu idx
  menu="$(HOME="$TMPHOME" ./mdoctor clean --interactive </dev/null 2>&1 || true)"
  idx="$(printf '%s\n' "$menu" | sed -n 's/^ *\[\([0-9][0-9]*\)\] *trash\(  .*\)*$/\1/p' | head -1)"
  [ -n "$idx" ] || { echo "trash module not found in interactive menu" >&2; return 1; }
  printf '%s\n' "$idx"
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME TRASH_DIR
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-interactive.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  # Use platform-aware trash directory
  TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
  if is_linux; then
    TRASH_DIR="$TMPHOME/.local/share/Trash/files"
  fi
  mkdir -p "$TRASH_DIR"
  echo "sample" > "$TRASH_DIR/interactive.txt"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "dry-run interactive selection (trash by menu index) does not delete" {
  # (Re)create the victim file so this test is independent of execution order.
  echo "sample" > "$TRASH_DIR/interactive.txt"
  local idx
  idx="$(trash_menu_index)"
  printf '%s\n' "$idx" | HOME="$TMPHOME" ./mdoctor clean --interactive >"$TMPHOME/dry_run.txt" 2>&1
  # The selected module name must appear in the run output — this proves
  # the derived index actually selected trash, not whatever sits at a
  # hardcoded position.
  assert_contains "$TMPHOME/dry_run.txt" "trash"
  assert_file_exists "$TRASH_DIR/interactive.txt"
}

@test "force interactive selection deletes trash after confirmation" {
  # Re-create the victim file: test ordering is not guaranteed and the
  # dry-run test must not depend on this one having run first.
  echo "sample" > "$TRASH_DIR/interactive.txt"
  local idx
  idx="$(trash_menu_index)"
  printf '%s\ny\n' "$idx" | HOME="$TMPHOME" ./mdoctor clean --interactive --force >"$TMPHOME/force_run.txt" 2>&1
  assert_contains "$TMPHOME/force_run.txt" "trash"
  assert_file_not_exists "$TRASH_DIR/interactive.txt"
}

@test "invalid interactive selection fails with non-zero exit" {
  local rc=0
  printf '99\n' | HOME="$TMPHOME" ./mdoctor clean --interactive >"$TMPHOME/invalid_run.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid interactive selection"
  # The specific error must be reported, not just any failure.
  assert_contains "$TMPHOME/invalid_run.txt" "Selection out of range"
}
