#!/usr/bin/env bash
#
# test_e2e_safe_mode.sh
# End-to-end test exercising every safe mdoctor command on macOS.
# All operations are read-only or dry-run — nothing is modified on the system.
#
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

cd "$ROOT_DIR"

# Track failures across subtests
_e2e_failures=0

_check() {
  # Wrapper: run an assertion, increment failure counter on error
  if ! "$@"; then
    _e2e_failures=$((_e2e_failures + 1))
  fi
}

run_ok() {
  local label="$1"
  shift
  local out="$TMPDIR_TEST/${label// /_}.txt"
  local rc=0
  "$@" >"$out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL [$label] expected exit 0, got $rc" >&2
    _e2e_failures=$((_e2e_failures + 1))
    echo ""
    return 0
  fi
  echo "$out"
}

run_fail() {
  local label="$1"
  shift
  local out="$TMPDIR_TEST/${label// /_}.txt"
  local rc=0
  "$@" >"$out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL [$label] expected non-zero exit, got 0" >&2
    _e2e_failures=$((_e2e_failures + 1))
    echo ""
    return 0
  fi
  echo "$out"
}

########################################
# 1. Version & Help
########################################

out=$(run_ok "version" ./mdoctor version)
[ -n "$out" ] && _check assert_contains "$out" "mdoctor"

out=$(run_ok "version-flag" ./mdoctor --version)
[ -n "$out" ] && _check assert_contains "$out" "mdoctor"

out=$(run_ok "help" ./mdoctor help)
[ -n "$out" ] && _check assert_contains "$out" "Usage"

out=$(run_ok "help-flag" ./mdoctor --help)
[ -n "$out" ] && _check assert_contains "$out" "Usage"

out=$(run_ok "no-args" ./mdoctor)
[ -n "$out" ] && _check assert_contains "$out" "Usage"

########################################
# 2. Subcommand Help
########################################

out=$(run_ok "check-help" ./mdoctor check --help)
[ -n "$out" ] && _check assert_contains "$out" "read-only"

out=$(run_ok "clean-help" ./mdoctor clean --help)
[ -n "$out" ] && _check assert_contains "$out" "dry-run"

out=$(run_ok "fix-help" ./mdoctor fix --help)
[ -n "$out" ] && _check assert_contains "$out" "Targets"

########################################
# 3. List Command
########################################

out=$(run_ok "list" ./mdoctor list)
if [ -n "$out" ]; then
  _check assert_contains "$out" "Check Modules"
  _check assert_contains "$out" "Cleanup Modules"
  _check assert_contains "$out" "Fix Targets"
fi

########################################
# 4. Info Command
########################################

out=$(run_ok "info" ./mdoctor info)
if [ -n "$out" ]; then
  _check assert_contains "$out" "System Information"
  _check assert_contains "$out" "OS:"
  _check assert_contains "$out" "CPU:"
fi

########################################
# 5. Full Health Check
########################################

out=$(run_ok "check-full" ./mdoctor check)
if [ -n "$out" ]; then
  _check assert_contains "$out" "Health score"
fi

# Verify a markdown report was generated
report_count=$(find /tmp -maxdepth 1 -name "mdoctor_report_*.md" -newer "$TMPDIR_TEST" 2>/dev/null | wc -l | tr -d ' ')
if [ "$report_count" -lt 1 ]; then
  echo "  WARN: no markdown report found in /tmp (may be expected if report path changed)" >&2
fi

########################################
# 6. Single Module Health Checks
########################################

out=$(run_ok "check-system" ./mdoctor check -m system)

out=$(run_ok "check-network" ./mdoctor check -m network)

########################################
# 7. JSON Output
########################################

out=$(run_ok "check-json" ./mdoctor check -m system --json)

########################################
# 8. Dry-Run Cleanup (full)
########################################

# Use temp HOME to isolate from user config
TMPHOME="$TMPDIR_TEST/home_clean_full"
mkdir -p "$TMPHOME/.config/mdoctor"
cat >"$TMPHOME/.config/mdoctor/cleanup_whitelist" <<'WL'
# empty whitelist for test
WL
mkdir -p "$TMPHOME/.Trash"

out=$(run_ok "clean-dryrun-full" env HOME="$TMPHOME" ./mdoctor clean)

########################################
# 9. Dry-Run Cleanup (single module)
########################################

TMPHOME2="$TMPDIR_TEST/home_clean_module"
mkdir -p "$TMPHOME2/.config/mdoctor"
cat >"$TMPHOME2/.config/mdoctor/cleanup_whitelist" <<'WL'
# empty
WL
mkdir -p "$TMPHOME2/.Trash"
echo "e2e-sample" >"$TMPHOME2/.Trash/e2e_test_file.txt"

out=$(run_ok "clean-dryrun-trash" env HOME="$TMPHOME2" ./mdoctor clean -m trash)

########################################
# 10. History Command
########################################

out=$(run_ok "history" ./mdoctor history)
[ -n "$out" ] && _check assert_contains "$out" "Health Score History"

########################################
# 11. Debug Mode
########################################

out=$(run_ok "check-debug" ./mdoctor check -m system --debug)

########################################
# 12. Error Handling
########################################

out=$(run_fail "bad-command" ./mdoctor badcommand)
[ -n "$out" ] && _check assert_contains "$out" "Unknown command"

out=$(run_fail "bad-check-module" ./mdoctor check -m nonexistent)
[ -n "$out" ] && _check assert_contains "$out" "Unknown check module"

out=$(run_fail "bad-clean-module" ./mdoctor clean -m nonexistent)

out=$(run_fail "fix-no-target" ./mdoctor fix)

out=$(run_fail "bad-fix-target" ./mdoctor fix nonexistent)
[ -n "$out" ] && _check assert_contains "$out" "Unknown fix target"

########################################
# 13. Safety Invariant: dry-run preserves files
########################################

_check assert_file_exists "$TMPHOME2/.Trash/e2e_test_file.txt"

########################################
# Summary
########################################

if [ "$_e2e_failures" -ne 0 ]; then
  fail "end-to-end safe mode ($_e2e_failures sub-test failures)"
else
  pass "end-to-end safe mode (all commands pass in safe/dry-run mode)"
fi
