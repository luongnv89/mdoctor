#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

cd "$ROOT_DIR"

./mdoctor check --help >"$TMPDIR_TEST/check_help.txt" 2>&1
./mdoctor clean --help >"$TMPDIR_TEST/clean_help.txt" 2>&1
./mdoctor fix --help >"$TMPDIR_TEST/fix_help.txt" 2>&1

assert_contains "$TMPDIR_TEST/check_help.txt" "--debug"
assert_contains "$TMPDIR_TEST/clean_help.txt" "--debug"
assert_contains "$TMPDIR_TEST/clean_help.txt" "Whitelist file"
assert_contains "$TMPDIR_TEST/clean_help.txt" "Scope file"
assert_contains "$TMPDIR_TEST/fix_help.txt" "--debug"

set +e
./mdoctor clean --not-a-real-option >"$TMPDIR_TEST/clean_bad_option.txt" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid clean option"
assert_contains "$TMPDIR_TEST/clean_bad_option.txt" "Unknown option"

pass "command parsing + help coverage"
