#!/usr/bin/env bats

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

@test "help output lists global options for check, clean and fix" {
  ./mdoctor check --help >"$TEST_TMP/check_help.txt" 2>&1
  ./mdoctor clean --help >"$TEST_TMP/clean_help.txt" 2>&1
  ./mdoctor fix --help >"$TEST_TMP/fix_help.txt" 2>&1
  assert_contains "$TEST_TMP/check_help.txt" "--debug"
  assert_contains "$TEST_TMP/clean_help.txt" "--debug"
  assert_contains "$TEST_TMP/clean_help.txt" "--interactive"
  assert_contains "$TEST_TMP/clean_help.txt" "Whitelist file"
  assert_contains "$TEST_TMP/clean_help.txt" "Scope file"
  assert_contains "$TEST_TMP/fix_help.txt" "--debug"
}

@test "unknown clean option fails and names the option" {
  local rc=0
  ./mdoctor clean --not-a-real-option >"$TEST_TMP/clean_bad_option.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid clean option"
  assert_contains "$TEST_TMP/clean_bad_option.txt" "Unknown option"
}

@test "unknown fix flag errors as an unknown option (not a target)" {
  # Task 1.2
  local rc=0
  ./mdoctor fix --nosuchflag >"$TEST_TMP/fix_bad_option.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid fix option"
  assert_contains "$TEST_TMP/fix_bad_option.txt" "Unknown option"
}

@test "macOS-only fix target refuses on Linux before any module code runs" {
  # Task 1.2: chown is never invoked (stub PATH records argv).
  if [ "$(uname -s)" != "Linux" ]; then
    skip "Linux-only gate check"
  fi
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  : >"$TEST_TMP/fix-gate-stubs.log"
  export MDOCTOR_STUB_LOG="$TEST_TMP/fix-gate-stubs.log"
  local rc=0
  ./mdoctor fix permissions >"$TEST_TMP/fix_permissions_linux.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for fix permissions on Linux"
  assert_contains "$TEST_TMP/fix_permissions_linux.txt" "macOS-only"
  assert_not_contains "$TEST_TMP/fix-gate-stubs.log" "chown"
}

@test "each guarded fix module refuses on Linux and executes zero macOS-only binaries" {
  # Task 1.3: module-level proof — the dispatch gate above never reaches
  # module code.
  if [ "$(uname -s)" != "Linux" ]; then
    skip "Linux-only gate check"
  fi
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  init_colors
  MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DIR
  export PATH="$ROOT_DIR/tests/helpers/bin-macos:$PATH"
  for _m in audio disk spotlight timemachine wifi bluetooth; do
    # shellcheck source=/dev/null
    source "$ROOT_DIR/fixes/${_m}.sh"
    : >"$TEST_TMP/fix-${_m}-stubs.log"
    export MDOCTOR_STUB_LOG="$TEST_TMP/fix-${_m}-stubs.log"
    local _rc=0
    _out="$(fix_${_m} 2>&1)" || _rc=$?
    [ "$_rc" -ne 0 ] || fail "Expected non-zero exit for fix ${_m} on Linux"
    echo "$_out" | grep -q "macOS-only" || fail "Expected macOS-only message for fix ${_m}"
    [ ! -s "$TEST_TMP/fix-${_m}-stubs.log" ] || fail "macOS-only binary executed by fix ${_m}: $(cat "$TEST_TMP/fix-${_m}-stubs.log")"
  done
}

@test "check-module allowlist rejects traversal without sourcing the payload" {
  # Task 3.3: the error text echoes the rejected name; the proof is the
  # missing canary: the payload file was never sourced.
  printf '#!/usr/bin/env bash\ntouch "%s/canary.txt"\n' "$TEST_TMP" >"$TEST_TMP/payload.sh"
  local rc=0
  ./mdoctor check -m ../../../../tmp/payload >"$TEST_TMP/check_traversal.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for traversal module name"
  assert_contains "$TEST_TMP/check_traversal.txt" "Unknown check module"
  [ ! -f "$TEST_TMP/canary.txt" ] || fail "Traversal module name sourced a file (canary exists)"
}

@test "module names with / or .. are rejected before path construction" {
  for _bad in "a/b" ".." "../apt" "-m"; do
    local rc=0
    ./mdoctor check -m "$_bad" >"$TEST_TMP/check_bad.txt" 2>&1 || rc=$?
    [ "${rc:-0}" -ne 0 ] || fail "Expected non-zero exit for module name '$_bad'"
  done
}

@test "existing-but-unregistered file is an unknown module, never a silent no-op" {
  local rc=0
  ./mdoctor check -m diagnose_performance >"$TEST_TMP/check_unreg.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for unregistered module file"
  assert_contains "$TEST_TMP/check_unreg.txt" "Unknown check module"
}

@test "apt is accepted on Linux and listed in help and error text" {
  if [ "$(uname -s)" != "Linux" ]; then
    skip "Linux-only module"
  fi
  ./mdoctor check --help >"$TEST_TMP/check_help_apt.txt" 2>&1
  assert_contains "$TEST_TMP/check_help_apt.txt" "apt"
  ./mdoctor check -m diagnose_performance >"$TEST_TMP/check_unreg.txt" 2>&1 || true
  assert_contains "$TEST_TMP/check_unreg.txt" "apt"
}
