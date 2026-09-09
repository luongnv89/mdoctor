#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Fixed metric inputs (issue #74, F-TEST-009/010): the DIAG_* overrides
# in checks/diagnose_performance.sh let these tests feed fixed inputs so
# both the healthy and the unhealthy branch are asserted deterministically
# instead of depending on the host's live metrics. The ps/ss stubs below
# neutralize the two host probes with no injectable source (top-CPU
# consumers, zombie scan, connection count) via the repo's established
# absence-degradation pattern: with no ps/ss on PATH those probes report
# skips instead of host-dependent findings.
run_diagnose_fixed() {
  local mode="$1"
  shift
  if [ "$mode" = "healthy" ]; then
    env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
      DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
      DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
      DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
      PATH="$TEST_TMP/nostub:$PATH" \
      ./mdoctor diagnose "$@"
  else
    env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_PCT="99" \
      DIAG_MEM_AVAIL_PCT="2" DIAG_MEM_PRESSURE_LEVEL="4" \
      DIAG_DISK_PCT="99" DIAG_SWAP_PCT="90" DIAG_LINUX_IOWAIT_PCT="50" \
      DIAG_CPU_USER_PCT="30" DIAG_CPU_SYS_PCT="60" \
      PATH="$TEST_TMP/nostub:$PATH" \
      ./mdoctor diagnose "$@"
  fi
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-diagnose.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/nostub"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/nostub/ps"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/nostub/ss"
  chmod +x "$TEST_TMP/nostub/ps" "$TEST_TMP/nostub/ss"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "diagnose --help displays usage and options" {
  ./mdoctor diagnose --help >"$TEST_TMP/diagnose_help.txt" 2>&1
  assert_contains "$TEST_TMP/diagnose_help.txt" "Usage: mdoctor diagnose"
  assert_contains "$TEST_TMP/diagnose_help.txt" "bottleneck detection"
  assert_contains "$TEST_TMP/diagnose_help.txt" "--debug"
  assert_contains "$TEST_TMP/diagnose_help.txt" "Memory"
  assert_contains "$TEST_TMP/diagnose_help.txt" "Disk I/O"
}

@test "help text includes diagnose command" {
  ./mdoctor help >"$TEST_TMP/help_output.txt" 2>&1
  assert_contains "$TEST_TMP/help_output.txt" "diagnose"
  assert_contains "$TEST_TMP/help_output.txt" "Active performance diagnosis"
}

@test "list command includes diagnose module" {
  ./mdoctor list >"$TEST_TMP/list_output.txt" 2>&1
  assert_contains "$TEST_TMP/list_output.txt" "Diagnose Modules"
  assert_contains "$TEST_TMP/list_output.txt" "diagnose"
  assert_contains "$TEST_TMP/list_output.txt" "performance"
}

@test "diagnose runs non-destructively and outputs all sections" {
  ./mdoctor diagnose >"$TEST_TMP/diagnose_output.txt" 2>&1
  # Content assertions (issue #74): the file must be non-empty and carry
  # every section — asserting mere existence is tautological since the
  # redirection above creates the file.
  [ -s "$TEST_TMP/diagnose_output.txt" ] || fail "diagnose produced no output"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Performance Diagnosis"
  assert_contains "$TEST_TMP/diagnose_output.txt" "CPU Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Memory Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Disk I/O Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Swap Thrashing Detection"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Zombie Process Detection"
  assert_contains "$TEST_TMP/diagnose_output.txt" "System Configuration"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Cross-Check Correlation"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Diagnosis Summary"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Diagnosis complete."
}

@test "diagnose --debug runs without errors" {
  ./mdoctor diagnose --debug >"$TEST_TMP/diagnose_debug.txt" 2>&1
  # Content assertion (issue #74): exit status alone is not enough, and
  # asserting the file exists is tautological — require real output.
  [ -s "$TEST_TMP/diagnose_debug.txt" ] || fail "diagnose --debug produced no output"
  assert_contains "$TEST_TMP/diagnose_debug.txt" "Performance Diagnosis"
  assert_contains "$TEST_TMP/diagnose_debug.txt" "Diagnosis complete."
}

@test "diagnose rejects unknown options with non-zero exit" {
  local rc=0
  ./mdoctor diagnose --invalid-option >"$TEST_TMP/diagnose_invalid.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid diagnose option"
  assert_contains "$TEST_TMP/diagnose_invalid.txt" "Unknown option"
}

@test "diagnose healthy branch reports System healthy with no recommendations" {
  # Fixed low inputs (issue #74): the healthy branch is asserted, never
  # skipped — the old guard (`if grep -q recommendation`) never ran on a
  # healthy idle machine while the pass line fired having asserted nothing.
  run_diagnose_fixed healthy >"$TEST_TMP/diagnose_healthy.txt" 2>&1
  assert_contains "$TEST_TMP/diagnose_healthy.txt" "Diagnosis Summary"
  assert_contains "$TEST_TMP/diagnose_healthy.txt" "System healthy"
  assert_contains "$TEST_TMP/diagnose_healthy.txt" "Diagnosis complete."
  assert_not_contains "$TEST_TMP/diagnose_healthy.txt" "recommendation(s)"
}

@test "diagnose unhealthy branch reports numbered recommendations" {
  # Fixed high inputs (issue #74): the unhealthy branch is asserted on
  # every host, including a healthy idle machine that would otherwise
  # never produce a recommendation.
  run_diagnose_fixed unhealthy >"$TEST_TMP/diagnose_unhealthy.txt" 2>&1
  assert_contains "$TEST_TMP/diagnose_unhealthy.txt" "Diagnosis Summary"
  assert_contains "$TEST_TMP/diagnose_unhealthy.txt" "recommendation(s)"
  assert_contains "$TEST_TMP/diagnose_unhealthy.txt" "[critical]"
  assert_not_contains "$TEST_TMP/diagnose_unhealthy.txt" "System healthy"
}

@test "diagnose output contains status indicators" {
  # Narrowed alternation (issue #74): the old five-way pattern accepted
  # essentially any output via its catch-all branches. A run must carry
  # the structural markers — the summary header and the completion
  # line — plus exactly one of the two mutually exclusive outcomes.
  # Asserted on fixed inputs, not the live host: runner health varies
  # (the Linux CI host is healthy, so a live run takes the healthy
  # branch there), and a bare `grep -q ... && fail ...` line fails under
  # bats either way — the assert_* helpers handle absence correctly.
  run_diagnose_fixed healthy >"$TEST_TMP/diagnose_indicators_healthy.txt" 2>&1
  assert_contains "$TEST_TMP/diagnose_indicators_healthy.txt" "Diagnosis Summary"
  assert_contains "$TEST_TMP/diagnose_indicators_healthy.txt" "Diagnosis complete."
  assert_contains "$TEST_TMP/diagnose_indicators_healthy.txt" "System healthy"
  assert_not_contains "$TEST_TMP/diagnose_indicators_healthy.txt" "recommendation(s)"
  run_diagnose_fixed unhealthy >"$TEST_TMP/diagnose_indicators_unhealthy.txt" 2>&1
  assert_contains "$TEST_TMP/diagnose_indicators_unhealthy.txt" "Diagnosis Summary"
  assert_contains "$TEST_TMP/diagnose_indicators_unhealthy.txt" "Diagnosis complete."
  assert_contains "$TEST_TMP/diagnose_indicators_unhealthy.txt" "recommendation(s)"
  assert_not_contains "$TEST_TMP/diagnose_indicators_unhealthy.txt" "System healthy"
}

@test "diagnose_performance.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/checks/diagnose_performance.sh"
  [ -x "$ROOT_DIR/checks/diagnose_performance.sh" ] || fail "diagnose_performance.sh should be executable"
}

@test "diagnose appears after fix and before info in help" {
  ./mdoctor help >"$TEST_TMP/help_ordered.txt" 2>&1
  local fix_line diagnose_line info_line
  fix_line=$(grep -n "^  fix " "$TEST_TMP/help_ordered.txt" | head -1 | cut -d: -f1)
  diagnose_line=$(grep -n "^  diagnose " "$TEST_TMP/help_ordered.txt" | head -1 | cut -d: -f1)
  info_line=$(grep -n "^  info " "$TEST_TMP/help_ordered.txt" | head -1 | cut -d: -f1)
  [ -n "$fix_line" ] || fail "fix command not found in help"
  [ -n "$diagnose_line" ] || fail "diagnose command not found in help"
  [ -n "$info_line" ] || fail "info command not found in help"
  (( diagnose_line > fix_line )) || fail "diagnose should appear after fix in help"
  (( info_line > diagnose_line )) || fail "info should appear after diagnose in help"
}

@test "diagnose recommendations follow numbered format" {
  # Unconditional (issue #74): the old `if grep -q recommendation` guard
  # skipped the assertion on a healthy machine. Fixed unhealthy inputs
  # guarantee recommendations, so the numbered format is always asserted.
  run_diagnose_fixed unhealthy >"$TEST_TMP/diagnose_numbered.txt" 2>&1
  sed 's/\x1b\[[0-9;]*m//g' "$TEST_TMP/diagnose_numbered.txt" >"$TEST_TMP/diagnose_numbered.clean.txt"
  grep -qE '^[0-9]+\. \[(critical|warning)\]' "$TEST_TMP/diagnose_numbered.clean.txt" \
    || fail "Expected numbered [critical]/[warning] recommendations in diagnose output"
}
