#!/usr/bin/env bats
# Task 2.9: `grep -c … || echo 0` double-fired "0\n0" into arithmetic on
# the healthy (zero-match) path. Both modules must be stderr-silent.
# Under tests/run.sh, apt-get/sudo are stubbed (no output), so the
# zero-match path is exercised deterministically.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "check -m security is stderr-silent on the zero-match path" {
  ./mdoctor check -m security >"$TEST_TMP/security.out" 2>"$TEST_TMP/security.err"
  assert_not_contains "$TEST_TMP/security.err" "syntax error"
  [ ! -s "$TEST_TMP/security.err" ] || fail "Expected empty stderr for check -m security"
}

@test "check -m updates is stderr-silent on the zero-match path" {
  ./mdoctor check -m updates >"$TEST_TMP/updates.out" 2>"$TEST_TMP/updates.err"
  assert_not_contains "$TEST_TMP/updates.err" "syntax error"
  [ ! -s "$TEST_TMP/updates.err" ] || fail "Expected empty stderr for check -m updates"
}
