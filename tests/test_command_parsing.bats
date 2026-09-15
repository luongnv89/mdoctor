#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-cmdparse.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
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

@test "-m/--module with no value errors cleanly for check and clean" {
  # Issue #105: under set -u a missing value crashed on
  # "$2: unbound variable"; the guard must name the flag and list the
  # platform-correct valid modules (registry-derived, like the
  # unknown-module error).
  local rc=0
  ./mdoctor check -m >"$TEST_TMP/check_m_missing.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'check -m'"
  assert_contains "$TEST_TMP/check_m_missing.txt" "-m/--module requires a module name"
  assert_contains "$TEST_TMP/check_m_missing.txt" "Available check modules"
  assert_contains "$TEST_TMP/check_m_missing.txt" "system"
  assert_not_contains "$TEST_TMP/check_m_missing.txt" "unbound variable"
  assert_not_contains "$TEST_TMP/check_m_missing.txt" "line "

  rc=0
  ./mdoctor check --module >"$TEST_TMP/check_module_missing.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'check --module'"
  assert_contains "$TEST_TMP/check_module_missing.txt" "-m/--module requires a module name"
  assert_not_contains "$TEST_TMP/check_module_missing.txt" "unbound variable"

  rc=0
  ./mdoctor clean -m >"$TEST_TMP/clean_m_missing.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'clean -m'"
  assert_contains "$TEST_TMP/clean_m_missing.txt" "-m/--module requires a module name"
  assert_contains "$TEST_TMP/clean_m_missing.txt" "Available modules"
  assert_contains "$TEST_TMP/clean_m_missing.txt" "trash"
  assert_not_contains "$TEST_TMP/clean_m_missing.txt" "unbound variable"
  assert_not_contains "$TEST_TMP/clean_m_missing.txt" "line "

  rc=0
  ./mdoctor clean --module >"$TEST_TMP/clean_module_missing.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'clean --module'"
  assert_contains "$TEST_TMP/clean_module_missing.txt" "-m/--module requires a module name"
  assert_not_contains "$TEST_TMP/clean_module_missing.txt" "unbound variable"
}

@test "history rejects global and unknown flags without an unbound-variable crash" {
  # Issue #233: a raw flag reached history_show as COUNT and
  # `(( total > count ))` evaluated it as a variable under set -u —
  # `mdoctor history --debug` died with "debug: unbound variable".
  for flag in --debug -h --help --not-a-real-option; do
    local rc=0
    ./mdoctor history "$flag" >"$TEST_TMP/history_flag.txt" 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'history $flag'"
    assert_contains "$TEST_TMP/history_flag.txt" "Unknown option"
    assert_not_contains "$TEST_TMP/history_flag.txt" "unbound variable"
  done
}

@test "history rejects a non-numeric count and extra positionals" {
  local rc=0
  ./mdoctor history bogus >"$TEST_TMP/history_bogus.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'history bogus'"
  assert_contains "$TEST_TMP/history_bogus.txt" "Invalid count"
  assert_not_contains "$TEST_TMP/history_bogus.txt" "unbound variable"

  rc=0
  ./mdoctor history 5 3 >"$TEST_TMP/history_extra.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for 'history 5 3'"
  assert_contains "$TEST_TMP/history_extra.txt" "Unknown argument"
}

@test "history still accepts no args and a bare count" {
  mkdir -p "$TEST_TMP/home"
  local rc=0
  HOME="$TEST_TMP/home" ./mdoctor history >"$TEST_TMP/history_ok.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "Expected exit 0 for bare 'history', got $rc"
  assert_contains "$TEST_TMP/history_ok.txt" "Health Score History"

  rc=0
  HOME="$TEST_TMP/home" ./mdoctor history 5 >"$TEST_TMP/history_count.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "Expected exit 0 for 'history 5', got $rc"
  assert_contains "$TEST_TMP/history_count.txt" "Health Score History"
}

@test "history treats leading-zero counts as decimal, not octal" {
  # Issue #241: `mdoctor history 08`/`09` passed the is_uint gate but
  # reached history_show's `(( total > count ))` as invalid octal,
  # leaking "value too great for base" to stderr while still exiting 0.
  # The arithmetic path only runs once history entries exist, so the
  # sandbox HOME below carries three fixture entries.
  mkdir -p "$TEST_TMP/home-octal/.mdoctor/history"
  local i
  for i in 1 2 3; do
    printf '{"timestamp":"2026-09-15T10:0%s:00Z","score":8%s,"rating":"good","warnings":%s,"failures":0}\n' \
      "$i" "$i" "$i" >"$TEST_TMP/home-octal/.mdoctor/history/20260915_10000${i}-1-${i}.json"
  done

  for n in 08 09; do
    local rc=0
    HOME="$TEST_TMP/home-octal" ./mdoctor history "$n" >"$TEST_TMP/history_octal_${n}.txt" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "Expected exit 0 for 'history $n', got $rc"
    assert_contains "$TEST_TMP/history_octal_${n}.txt" "Health Score History"
    assert_not_contains "$TEST_TMP/history_octal_${n}.txt" "value too great for base"
    assert_not_contains "$TEST_TMP/history_octal_${n}.txt" "unbound variable"
  done

  # Leading-zero counts must render exactly like their decimal forms.
  local rc=0
  HOME="$TEST_TMP/home-octal" ./mdoctor history 8 >"$TEST_TMP/history_8.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "Expected exit 0 for 'history 8', got $rc"
  cmp -s "$TEST_TMP/history_8.txt" "$TEST_TMP/history_octal_08.txt" ||
    fail "Expected 'history 08' output to equal 'history 8'"
}

@test "info, list, benchmark, version and help reject unknown args cleanly" {
  # Issue #233: these commands bypass parse_common_args and used to
  # silently drop every argument (or crash on it). The Global Options
  # are documented only for the commands that parse them, so every
  # other command fails with a clean usage error instead.
  for cmd in info list benchmark version help; do
    local rc=0
    ./mdoctor "$cmd" --debug >"$TEST_TMP/${cmd}_debug.txt" 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || fail "Expected non-zero exit for '$cmd --debug'"
    assert_contains "$TEST_TMP/${cmd}_debug.txt" "Unknown option"
    assert_not_contains "$TEST_TMP/${cmd}_debug.txt" "unbound variable"

    rc=0
    ./mdoctor "$cmd" -h >"$TEST_TMP/${cmd}_h.txt" 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || fail "Expected non-zero exit for '$cmd -h'"
    assert_contains "$TEST_TMP/${cmd}_h.txt" "Unknown option"
    assert_not_contains "$TEST_TMP/${cmd}_h.txt" "unbound variable"
  done
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
