#!/usr/bin/env bats
# Task 4.7: EXIT handlers stack instead of clobbering each other.
# Bash traps replace rather than stack, so every EXIT-time action must go
# through the ordered hook list in lib/common.sh (register_exit_hook);
# a bare `trap ... EXIT` anywhere in the session path silently discards
# the previously installed handler (e.g. the spinner start used to eat
# cleanup.sh's session-end trap, losing the operations-log record).

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME
  TMPHOME="${HOME}/.mdoctor-test-exit-hooks.$$.$RANDOM"
  mkdir -p "$TMPHOME"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "no bare EXIT trap remains outside the hook list" {
  bare_traps="$(grep -rn '^[[:space:]]*trap ' lib/common.sh cleanup.sh lib/benchmark.sh 2>/dev/null | grep 'EXIT' | grep -v '_run_exit_hooks' || true)"
  [ -z "$bare_traps" ] || fail "bare EXIT trap(s) remain outside the hook list: $bare_traps"
}

@test "interactive (tty) cleanup run records its session-end entry" {
  if ! command -v script >/dev/null 2>&1; then
    skip "script(1) unavailable for tty session-end test"
  fi
  rm -rf "$TMPHOME/.config"
  if is_macos; then
    HOME="$TMPHOME" script -q /dev/null ./cleanup.sh >/dev/null 2>&1 || true
  else
    HOME="$TMPHOME" script -qec "./cleanup.sh" /dev/null >/dev/null 2>&1 || true
  fi
  assert_contains "$TMPHOME/.config/mdoctor/operations.log" "session end"
}
