#!/usr/bin/env bats
#
# test_e2e_safe_mode.bats
# End-to-end test exercising every safe mdoctor command.
# All operations are read-only or dry-run — nothing is modified on the system.
# Runs on macOS and Linux; long-running commands are guarded with timeouts.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Per-command timeout (seconds) to prevent hangs in CI
_CMD_TIMEOUT=280

_run_with_timeout() {
  # Run a command with timeout; fall back to direct exec if unavailable
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP TMPHOME TMPHOME2 E2E_ENV_OK _IS_MACOS
  TEST_TMP="$(mktemp -d)"
  # Skip in minimal environments (e.g. bash:3.2 Docker) that lack basic tools
  if ! command -v uname >/dev/null 2>&1 || ! command -v find >/dev/null 2>&1; then
    E2E_ENV_OK=false
    return 0
  fi
  E2E_ENV_OK=true
  _IS_MACOS=false
  [ "$(uname -s)" = "Darwin" ] && _IS_MACOS=true

  # Dry-run cleanups use temp HOMEs to isolate from user config
  TMPHOME="$TEST_TMP/home_clean_full"
  mkdir -p "$TMPHOME/.config/mdoctor" "$TMPHOME/.Trash"
  cat >"$TMPHOME/.config/mdoctor/cleanup_whitelist" <<'WL'
# empty whitelist for test
WL

  TMPHOME2="$TEST_TMP/home_clean_module"
  mkdir -p "$TMPHOME2/.config/mdoctor" "$TMPHOME2/.Trash"
  cat >"$TMPHOME2/.config/mdoctor/cleanup_whitelist" <<'WL'
# empty
WL
  echo "e2e-sample" >"$TMPHOME2/.Trash/e2e_test_file.txt"
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

setup() {
  if [ "${E2E_ENV_OK:-}" != true ]; then
    skip "e2e test requires a full OS environment"
  fi
}

_run_ok() {
  # $1 label; rest: command. Output file on success, empty on failure.
  local label="$1"
  shift
  local out="$TEST_TMP/e2e_${label// /_}.txt"
  local rc=0
  _run_with_timeout "$@" >"$out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL [$label] expected exit 0, got $rc" >&2
    echo ""
    return 1
  fi
  echo "$out"
}

_run_fail() {
  # $1 label; rest: command. Output file when the command failed as expected.
  local label="$1"
  shift
  local out="$TEST_TMP/e2e_${label// /_}.txt"
  local rc=0
  _run_with_timeout "$@" >"$out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL [$label] expected non-zero exit, got 0" >&2
    echo ""
    return 1
  fi
  echo "$out"
}

@test "e2e: version, help and bare invocation" {
  local out
  out=$(_run_ok "version" ./mdoctor version) && assert_contains "$out" "mdoctor"
  out=$(_run_ok "version-flag" ./mdoctor --version) && assert_contains "$out" "mdoctor"
  out=$(_run_ok "help" ./mdoctor help) && assert_contains "$out" "Usage"
  out=$(_run_ok "help-flag" ./mdoctor --help) && assert_contains "$out" "Usage"
  out=$(_run_ok "no-args" ./mdoctor) && assert_contains "$out" "Usage"
}

@test "e2e: subcommand help" {
  local out
  out=$(_run_ok "check-help" ./mdoctor check --help) && assert_contains "$out" "read-only"
  out=$(_run_ok "clean-help" ./mdoctor clean --help) && assert_contains "$out" "dry-run"
  out=$(_run_ok "fix-help" ./mdoctor fix --help) && assert_contains "$out" "Targets"
}

@test "e2e: list command" {
  local out
  out=$(_run_ok "list" ./mdoctor list)
  assert_contains "$out" "Check Modules"
  assert_contains "$out" "Cleanup Modules"
  assert_contains "$out" "Fix Targets"
}

@test "e2e: info command" {
  local out
  out=$(_run_ok "info" ./mdoctor info)
  assert_contains "$out" "System Information"
  assert_contains "$out" "OS:"
  assert_contains "$out" "CPU:"
}

@test "e2e: single module health checks" {
  local out
  out=$(_run_ok "check-system" ./mdoctor check -m system)
  # Network check uses nslookup/ping which can hang in minimal CI containers
  if [ "$_IS_MACOS" = true ]; then
    _run_ok "check-network" ./mdoctor check -m network >/dev/null
  fi
}

@test "e2e: JSON output carries the real version (macOS)" {
  _run_ok "check-json" ./mdoctor check -m system --json >/dev/null
  # Task 5.4: the JSON report carries MDOCTOR_VERSION via env propagation
  # into doctor.sh — no literal fallback remains, so the field must be the
  # real version, never null. Only the full audit emits JSON, so like the
  # full-check section this is gated to macOS (avoids the docker/nslookup
  # hang risk on Linux CI).
  if [ "$_IS_MACOS" != true ]; then
    skip "full JSON audit runs on macOS only"
  fi
  local out
  out=$(_run_ok "check-json-full" ./mdoctor check --json)
  assert_contains "$out" '"version": "3.0.0"'
  assert_not_contains "$out" '"version": null'
}

@test "e2e: dry-run cleanup (full and single module)" {
  local out
  out=$(_run_ok "clean-dryrun-full" env HOME="$TMPHOME" ./mdoctor clean)
  out=$(_run_ok "clean-dryrun-trash" env HOME="$TMPHOME2" ./mdoctor clean -m trash)
}

@test "e2e: history command" {
  local out
  out=$(_run_ok "history" ./mdoctor history) && assert_contains "$out" "Health Score History"
}

@test "e2e: debug mode" {
  _run_ok "check-debug" ./mdoctor check -m system --debug >/dev/null
}

@test "e2e: error handling for unknown commands and modules" {
  local out
  out=$(_run_fail "bad-command" ./mdoctor badcommand) && assert_contains "$out" "Unknown command"
  out=$(_run_fail "bad-check-module" ./mdoctor check -m nonexistent) && assert_contains "$out" "Unknown check module"
  _run_fail "bad-clean-module" ./mdoctor clean -m nonexistent >/dev/null
  _run_fail "fix-no-target" ./mdoctor fix >/dev/null
  out=$(_run_fail "bad-fix-target" ./mdoctor fix nonexistent) && assert_contains "$out" "Unknown fix target"
}

@test "e2e: safety invariant — dry-run preserves files" {
  assert_file_exists "$TMPHOME2/.Trash/e2e_test_file.txt"
}
