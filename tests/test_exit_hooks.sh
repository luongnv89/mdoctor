#!/usr/bin/env bash
# Task 4.7: EXIT handlers stack instead of clobbering each other.
# Bash traps replace rather than stack, so every EXIT-time action must go
# through the ordered hook list in lib/common.sh (register_exit_hook);
# a bare `trap ... EXIT` anywhere in the session path silently discards
# the previously installed handler (e.g. the spinner start used to eat
# cleanup.sh's session-end trap, losing the operations-log record).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-exit-hooks.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

cd "$ROOT_DIR"

# Static guard: no bare EXIT trap may remain in the session path. The only
# allowed installer is the hook runner in lib/common.sh.
bare_traps="$(grep -rn '^[[:space:]]*trap ' lib/common.sh cleanup.sh lib/benchmark.sh 2>/dev/null | grep 'EXIT' | grep -v '_run_exit_hooks' || true)"
[ -z "$bare_traps" ] || fail "bare EXIT trap(s) remain outside the hook list: $bare_traps"

# Behavioral guard: an interactive (tty) cleanup run must still record its
# session-end entry — i.e. the spinner start did not clobber the session
# handler. Needs script(1); skip without it.
if command -v script >/dev/null 2>&1; then
  rm -rf "$TMPHOME/.config"
  if is_macos; then
    HOME="$TMPHOME" script -q /dev/null ./cleanup.sh >/dev/null 2>&1 || true
  else
    HOME="$TMPHOME" script -qec "./cleanup.sh" /dev/null >/dev/null 2>&1 || true
  fi
  assert_contains "$TMPHOME/.config/mdoctor/operations.log" "session end"
else
  echo "SKIP: script(1) unavailable for tty session-end test" >&2
fi

pass "ordered exit hooks + tty session-end record"
