#!/usr/bin/env bash
# Task 2.9: `grep -c … || echo 0` double-fired "0\n0" into arithmetic on
# the healthy (zero-match) path. Both modules must be stderr-silent.
# Under tests/run.sh, apt-get/sudo are stubbed (no output), so the
# zero-match path is exercised deterministically.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

cd "$ROOT_DIR"

./mdoctor check -m security >"$TMPD/security.out" 2>"$TMPD/security.err"
assert_not_contains "$TMPD/security.err" "syntax error"
[ ! -s "$TMPD/security.err" ] || fail "Expected empty stderr for check -m security"

./mdoctor check -m updates >"$TMPD/updates.out" 2>"$TMPD/updates.err"
assert_not_contains "$TMPD/updates.err" "syntax error"
[ ! -s "$TMPD/updates.err" ] || fail "Expected empty stderr for check -m updates"

pass "zero-match modules are stderr-silent"
