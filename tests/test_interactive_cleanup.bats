#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

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

@test "dry-run interactive selection (module 1 = trash) does not delete" {
  printf '1\n' | HOME="$TMPHOME" ./mdoctor clean --interactive >/dev/null 2>&1
  assert_file_exists "$TRASH_DIR/interactive.txt"
}

@test "force interactive selection deletes after confirmation" {
  printf '1\ny\n' | HOME="$TMPHOME" ./mdoctor clean --interactive --force >/dev/null 2>&1
  assert_file_not_exists "$TRASH_DIR/interactive.txt"
}

@test "invalid interactive selection fails with non-zero exit" {
  local rc=0
  printf '99\n' | HOME="$TMPHOME" ./mdoctor clean --interactive >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid interactive selection"
}
