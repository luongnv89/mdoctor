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
assert_contains "$TMPDIR_TEST/clean_help.txt" "--interactive"
assert_contains "$TMPDIR_TEST/clean_help.txt" "Whitelist file"
assert_contains "$TMPDIR_TEST/clean_help.txt" "Scope file"
assert_contains "$TMPDIR_TEST/fix_help.txt" "--debug"

set +e
./mdoctor clean --not-a-real-option >"$TMPDIR_TEST/clean_bad_option.txt" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid clean option"
assert_contains "$TMPDIR_TEST/clean_bad_option.txt" "Unknown option"

# Task 1.2: a mistyped fix flag errors as an unknown option (not a target).
set +e
./mdoctor fix --nosuchflag >"$TMPDIR_TEST/fix_bad_option.txt" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid fix option"
assert_contains "$TMPDIR_TEST/fix_bad_option.txt" "Unknown option"

# Task 1.2: on Linux, macOS-only fix targets refuse before any module
# code runs — chown is never invoked (stub PATH records argv).
if [ "$(uname -s)" = "Linux" ]; then
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  : >"$TMPDIR_TEST/fix-gate-stubs.log"
  export MDOCTOR_STUB_LOG="$TMPDIR_TEST/fix-gate-stubs.log"
  set +e
  ./mdoctor fix permissions >"$TMPDIR_TEST/fix_permissions_linux.txt" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for fix permissions on Linux"
  assert_contains "$TMPDIR_TEST/fix_permissions_linux.txt" "macOS-only"
  assert_not_contains "$TMPDIR_TEST/fix-gate-stubs.log" "chown"
fi

# Task 1.3: each guarded fix module refuses on Linux with a platform
# message and executes zero macOS-only binaries (module-level proof —
# the dispatch gate above never reaches module code).
if [ "$(uname -s)" = "Linux" ]; then
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  init_colors
  MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DIR
  export PATH="$ROOT_DIR/tests/helpers/bin-macos:$PATH"
  for _m in audio disk spotlight timemachine wifi bluetooth; do
    # shellcheck source=/dev/null
    source "$ROOT_DIR/fixes/${_m}.sh"
    : >"$TMPDIR_TEST/fix-${_m}-stubs.log"
    export MDOCTOR_STUB_LOG="$TMPDIR_TEST/fix-${_m}-stubs.log"
    set +e
    _out="$("fix_${_m}" 2>&1)"
    _rc=$?
    set -e
    [ "$_rc" -ne 0 ] || fail "Expected non-zero exit for fix ${_m} on Linux"
    echo "$_out" | grep -q "macOS-only" || fail "Expected macOS-only message for fix ${_m}"
    [ ! -s "$TMPDIR_TEST/fix-${_m}-stubs.log" ] || fail "macOS-only binary executed by fix ${_m}: $(cat "$TMPDIR_TEST/fix-${_m}-stubs.log")"
  done
fi

pass "command parsing + help coverage"
