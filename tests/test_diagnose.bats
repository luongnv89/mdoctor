#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-diagnose.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
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
  assert_file_exists "$TEST_TMP/diagnose_output.txt"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Performance Diagnosis"
  assert_contains "$TEST_TMP/diagnose_output.txt" "CPU Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Memory Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Disk I/O Diagnostics"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Swap Thrashing Detection"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Zombie Process Detection"
  assert_contains "$TEST_TMP/diagnose_output.txt" "System Configuration"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Cross-Check Correlation"
  assert_contains "$TEST_TMP/diagnose_output.txt" "Diagnosis Summary"
}

@test "diagnose --debug runs without errors" {
  ./mdoctor diagnose --debug >"$TEST_TMP/diagnose_debug.txt" 2>&1
  assert_file_exists "$TEST_TMP/diagnose_debug.txt"
}

@test "diagnose rejects unknown options with non-zero exit" {
  local rc=0
  ./mdoctor diagnose --invalid-option >"$TEST_TMP/diagnose_invalid.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid diagnose option"
  assert_contains "$TEST_TMP/diagnose_invalid.txt" "Unknown option"
}

@test "diagnose output contains status indicators" {
  local output
  output="$(./mdoctor diagnose 2>&1)"
  echo "$output" | grep -qE '(✅|⚠|Diagnosis complete|recommendation|System healthy)' || fail "Expected status indicators in diagnose output"
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
  local output
  output="$(./mdoctor diagnose 2>&1)"
  # If there are recommendations, they should be numbered (strip ANSI codes first)
  if echo "$output" | grep -q "recommendation"; then
    echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -qE '^[0-9]+\.' || fail "Expected numbered recommendations in diagnose output"
  fi
}
