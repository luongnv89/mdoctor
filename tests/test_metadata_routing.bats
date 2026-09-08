#!/usr/bin/env bats

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "mdoctor list shows cross-platform check modules" {
  ./mdoctor list >"$TEST_TMP/list.txt" 2>&1
  assert_contains "$TEST_TMP/list.txt" "network"
  assert_contains "$TEST_TMP/list.txt" "containers"
}

@test "mdoctor list shows macOS-only modules on macOS" {
  if ! is_macos; then
    skip "macOS-only modules"
  fi
  ./mdoctor list >"$TEST_TMP/list.txt" 2>&1
  assert_contains "$TEST_TMP/list.txt" "battery"
  assert_contains "$TEST_TMP/list.txt" "homebrew"
  assert_contains "$TEST_TMP/list.txt" "spotlight"
}

@test "mdoctor list shows cleanup and fix modules" {
  ./mdoctor list >"$TEST_TMP/list.txt" 2>&1
  assert_contains "$TEST_TMP/list.txt" "trash"
  assert_contains "$TEST_TMP/list.txt" "dev_caches"
  assert_contains "$TEST_TMP/list.txt" "dns"
}
