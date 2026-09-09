#!/usr/bin/env bats
#
# test_e2e_safe_mode.bats
# End-to-end test exercising every safe mdoctor command.
# All operations are read-only or dry-run — nothing is modified on the system.
# Runs on macOS and Linux; long-running commands are guarded with timeouts.

load 'helpers/assert'
load 'helpers/fixture'

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

_e2e_hermetic_path() {
  # Sparse PATH farm (same pattern as test_check_modules.bats): the
  # suite-wide stubs first, then every host binary except the probes that
  # can hang CI — so the shared full audit below stays fast and hang-free
  # on every platform.
  echo "$ROOT_DIR/tests/helpers/bin:$TEST_TMP/farm"
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP TMPHOME TMPHOME2 E2E_ENV_OK E2E_SKIP_REASON _IS_MACOS
  export E2E_JSON_OUT E2E_REPORT E2E_AUDIT_RC
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-e2e.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  # Explicit capability gate (issue #73): the e2e lane needs a full OS
  # environment on Bash >= 4. A job-set MDOCTOR_E2E_SKIP flag forces the
  # skip; otherwise the Bash major version decides — never a probe for
  # utilities (uname/find) that minimal images like bash:3.2 also ship,
  # which is why the old guard never fired there.
  if [ -n "${MDOCTOR_E2E_SKIP:-}" ]; then
    E2E_ENV_OK=false
    E2E_SKIP_REASON="MDOCTOR_E2E_SKIP is set"
    return 0
  fi
  case "${BASH_VERSION:-}" in
    4.*|5.*) ;;
    *)
      E2E_ENV_OK=false
      E2E_SKIP_REASON="bash ${BASH_VERSION:-unknown} < 4"
      return 0
      ;;
  esac
  E2E_ENV_OK=true
  E2E_SKIP_REASON=""
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

  # Sparse PATH farm for the shared full audit (see _e2e_hermetic_path).
  mkdir -p "$TEST_TMP/farm" "$TEST_TMP/home"
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        ping|nslookup|ss|ps|softwareupdate) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done

  # Shared full audit (issue #74): one hermetic `check --json` run feeds
  # both the JSON schema test and the deterministic-path report test, so
  # the file pays for a full audit only once. MDOCTOR_REPORT_MD pins the
  # markdown report to a known path instead of a fresh mktemp file.
  E2E_JSON_OUT="$TEST_TMP/e2e_full_json.out"
  E2E_REPORT="$TEST_TMP/e2e-report.md"
  E2E_AUDIT_RC=0
  PATH="$(_e2e_hermetic_path)" HOME="$TEST_TMP/home" \
    MDOCTOR_REPORT_MD="$E2E_REPORT" \
    _run_with_timeout ./mdoctor check --json \
    >"$E2E_JSON_OUT" 2>"$TEST_TMP/e2e_full_json.err" || E2E_AUDIT_RC=$?
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

setup() {
  if [ "${E2E_ENV_OK:-}" != true ]; then
    skip "e2e test requires a full OS environment (${E2E_SKIP_REASON:-missing capabilities})"
  fi
}

_require_audit() {
  # Fail — never warn — when the shared full audit did not succeed, so a
  # broken audit can never silently green the JSON/report tests.
  if [ "${E2E_AUDIT_RC:-1}" -ne 0 ]; then
    tail -n 20 "$TEST_TMP/e2e_full_json.err" >&2 || true
    fail "shared full audit 'mdoctor check --json' exited ${E2E_AUDIT_RC:-?} (expected 0)"
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
  out=$(_run_ok "check-system" ./mdoctor check -m system) && assert_contains "$out" "OS:"
  # Network check uses nslookup/ping which can hang in minimal CI containers
  if [ "$_IS_MACOS" = true ]; then
    out=$(_run_ok "check-network" ./mdoctor check -m network) && assert_contains "$out" "Network Diagnostics"
  fi
}

@test "e2e: JSON output parses and matches the schema" {
  # The JSON document is piped through a real parser (issue #74,
  # F-TEST-011) — string-grep alone would stay green on malformed JSON.
  _require_audit
  awk '/^\{/{flag=1} flag{print} /^\}/{if (flag) exit}' \
    "$E2E_JSON_OUT" >"$TEST_TMP/e2e_json_doc.json"
  [ -s "$TEST_TMP/e2e_json_doc.json" ] || fail "no JSON document found in 'mdoctor check --json' output"
  # The JSON report carries MDOCTOR_VERSION (Task 5.4: single source of
  # truth, no literal fallback) — the bare release version, without the
  # `+commit` suffix that `mdoctor version` appends in dev trees.
  local expect_version
  expect_version="$(./mdoctor version | awk '{print $2}' | cut -d+ -f1)"
  if command -v python3 >/dev/null 2>&1; then
    MDOCTOR_EXPECT_VERSION="$expect_version" python3 - "$TEST_TMP/e2e_json_doc.json" <<'PYEOF' || fail "JSON schema assertion failed (see above)"
import json, os, sys
with open(sys.argv[1]) as f:
    doc = json.load(f)  # malformed JSON raises -> suite fails
assert isinstance(doc["version"], str) and doc["version"], "version must be a non-empty string"
assert doc["version"] == os.environ["MDOCTOR_EXPECT_VERSION"], \
    "version %r != dispatcher version %r" % (doc["version"], os.environ["MDOCTOR_EXPECT_VERSION"])
assert isinstance(doc["timestamp"], str) and doc["timestamp"], "timestamp must be a non-empty string"
assert isinstance(doc["hostname"], str) and doc["hostname"], "hostname must be a non-empty string"
assert isinstance(doc["score"], int) and 0 <= doc["score"] <= 100, "score must be an int in 0..100"
assert isinstance(doc["rating"], str) and doc["rating"], "rating must be a non-empty string"
assert isinstance(doc["warnings"], int) and doc["warnings"] >= 0, "warnings must be a non-negative int"
assert isinstance(doc["failures"], int) and doc["failures"] >= 0, "failures must be a non-negative int"
assert isinstance(doc["actions"], list), "actions must be an array"
assert isinstance(doc["checks"], list), "checks must be an array"
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    jq -e '(.version | type == "string" and length > 0)
      and (.timestamp | type == "string" and length > 0)
      and (.hostname | type == "string" and length > 0)
      and (.score | type == "number" and . >= 0 and . <= 100)
      and (.rating | type == "string" and length > 0)
      and (.warnings | type == "number" and . >= 0)
      and (.failures | type == "number" and . >= 0)
      and (.actions | type == "array")
      and (.checks | type == "array")
      and (.version == $MDOCTOR_EXPECT_VERSION)' \
      --arg MDOCTOR_EXPECT_VERSION "$expect_version" \
      "$TEST_TMP/e2e_json_doc.json" >/dev/null \
      || fail "JSON schema assertion failed (jq)"
  else
    skip "no JSON parser available (need python3 or jq)"
  fi
}

@test "e2e: markdown report is written to the deterministic override path" {
  # The report-generation check (issue #74): MDOCTOR_REPORT_MD pins the
  # report location, and this test fails — it never degrades to a stderr
  # warning — when the report is missing or lacks the expected content.
  _require_audit
  assert_file_exists "$E2E_REPORT"
  [ -s "$E2E_REPORT" ] || fail "markdown report is empty: $E2E_REPORT"
  assert_contains "$E2E_REPORT" "# mdoctor System Health Report"
  assert_contains "$E2E_REPORT" "Health score"
  assert_contains "$E2E_REPORT" "_End of report._"
}

@test "e2e: dry-run cleanup (full and single module)" {
  local out
  out=$(_run_ok "clean-dryrun-full" env HOME="$TMPHOME" ./mdoctor clean)
  assert_contains "$out" "DRY_RUN=true"
  assert_contains "$out" "Emptying Trash"
  out=$(_run_ok "clean-dryrun-trash" env HOME="$TMPHOME2" ./mdoctor clean -m trash)
  assert_contains "$out" "Emptying Trash"
}

@test "e2e: history command" {
  local out
  out=$(_run_ok "history" ./mdoctor history) && assert_contains "$out" "Health Score History"
}

@test "e2e: debug mode" {
  local out
  out=$(_run_ok "check-debug" ./mdoctor check -m system --debug) && assert_contains "$out" "DEBUG"
}

@test "e2e: error handling for unknown commands and modules" {
  local out
  out=$(_run_fail "bad-command" ./mdoctor badcommand) && assert_contains "$out" "Unknown command"
  out=$(_run_fail "bad-check-module" ./mdoctor check -m nonexistent) && assert_contains "$out" "Unknown check module"
  out=$(_run_fail "bad-clean-module" ./mdoctor clean -m nonexistent) && assert_contains "$out" "Unknown cleanup module"
  out=$(_run_fail "fix-no-target" ./mdoctor fix) && assert_contains "$out" "Usage: mdoctor fix"
  out=$(_run_fail "bad-fix-target" ./mdoctor fix nonexistent) && assert_contains "$out" "Unknown fix target"
}

@test "e2e: safety invariant — dry-run preserves files" {
  assert_file_exists "$TMPHOME2/.Trash/e2e_test_file.txt"
}
