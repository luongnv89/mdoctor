#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

cd "$ROOT_DIR"

########################################
# TEST: diagnose command exists and is discoverable
########################################

# Test 1: mdoctor diagnose --help works
./mdoctor diagnose --help >"$TMPDIR_TEST/diagnose_help.txt" 2>&1
assert_contains "$TMPDIR_TEST/diagnose_help.txt" "Usage: mdoctor diagnose"
assert_contains "$TMPDIR_TEST/diagnose_help.txt" "bottleneck detection"
assert_contains "$TMPDIR_TEST/diagnose_help.txt" "--debug"
assert_contains "$TMPDIR_TEST/diagnose_help.txt" "Memory"
assert_contains "$TMPDIR_TEST/diagnose_help.txt" "Disk I/O"
pass "diagnose --help displays usage and options"

########################################
# TEST: diagnose command in help listing
########################################

# Test 2: mdoctor help includes diagnose
./mdoctor help >"$TMPDIR_TEST/help_output.txt" 2>&1
assert_contains "$TMPDIR_TEST/help_output.txt" "diagnose"
assert_contains "$TMPDIR_TEST/help_output.txt" "Active performance diagnosis"
pass "help text includes diagnose command"

########################################
# TEST: diagnose command in list modules
########################################

# Test 3: mdoctor list includes diagnose module
./mdoctor list >"$TMPDIR_TEST/list_output.txt" 2>&1
assert_contains "$TMPDIR_TEST/list_output.txt" "Diagnose Modules"
assert_contains "$TMPDIR_TEST/list_output.txt" "diagnose"
assert_contains "$TMPDIR_TEST/list_output.txt" "performance"
pass "list command includes diagnose module"

########################################
# TEST: diagnose command runs without errors
########################################

# Test 4: mdoctor diagnose runs non-destructively (non-zero output)
./mdoctor diagnose >"$TMPDIR_TEST/diagnose_output.txt" 2>&1
assert_file_exists "$TMPDIR_TEST/diagnose_output.txt"

# Check that the output contains expected sections
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Performance Diagnosis"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "CPU Diagnostics"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Memory Diagnostics"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Disk I/O Diagnostics"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Swap Thrashing Detection"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Zombie Process Detection"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "System Configuration"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Cross-Check Correlation"
assert_contains "$TMPDIR_TEST/diagnose_output.txt" "Diagnosis Summary"
pass "diagnose runs without errors and outputs all sections"

########################################
# TEST: diagnose --debug runs without errors
########################################

# Test 5: mdoctor diagnose --debug runs without errors
./mdoctor diagnose --debug >"$TMPDIR_TEST/diagnose_debug.txt" 2>&1
assert_file_exists "$TMPDIR_TEST/diagnose_debug.txt"
pass "diagnose --debug runs without errors"

########################################
# TEST: diagnose rejects unknown options
########################################

# Test 6: Unknown option returns non-zero exit
set +e
./mdoctor diagnose --invalid-option >"$TMPDIR_TEST/diagnose_invalid.txt" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid diagnose option"
assert_contains "$TMPDIR_TEST/diagnose_invalid.txt" "Unknown option"
pass "diagnose rejects unknown options with non-zero exit"

########################################
# TEST: diagnose output contains severity indicators
########################################

# Test 7: Output contains status icons (check, warn, fail, or info indicators)
output="$($ROOT_DIR/mdoctor diagnose 2>&1)"
# At least some status indicators should appear
echo "$output" | grep -qE '(✅|⚠|Diagnosis complete|recommendation|System healthy)' || fail "Expected status indicators in diagnose output"
pass "diagnose output contains status indicators"

########################################
# TEST: diagnose check module file exists
########################################

# Test 8: The check module file exists and is executable
assert_file_exists "$ROOT_DIR/checks/diagnose_performance.sh"
[ -x "$ROOT_DIR/checks/diagnose_performance.sh" ] || fail "diagnose_performance.sh should be executable"
pass "diagnose_performance.sh exists and is executable"

########################################
# TEST: diagnose is listed in mdoctor help alongside other commands
########################################

# Test 9: Verify diagnose appears in the correct position in help output
./mdoctor help >"$TMPDIR_TEST/help_ordered.txt" 2>&1
# diagnose should appear after fix and before info
fix_line=$(grep -n "^  fix " "$TMPDIR_TEST/help_ordered.txt" | head -1 | cut -d: -f1)
diagnose_line=$(grep -n "^  diagnose " "$TMPDIR_TEST/help_ordered.txt" | head -1 | cut -d: -f1)
info_line=$(grep -n "^  info " "$TMPDIR_TEST/help_ordered.txt" | head -1 | cut -d: -f1)

[ -n "$fix_line" ] || fail "fix command not found in help"
[ -n "$diagnose_line" ] || fail "diagnose command not found in help"
[ -n "$info_line" ] || fail "info command not found in help"

(( diagnose_line > fix_line )) || fail "diagnose should appear after fix in help"
(( info_line > diagnose_line )) || fail "info should appear after diagnose in help"
pass "diagnose command appears in correct order in help"

########################################
# TEST: diagnose output contains actionable recommendations format
########################################

# Test 10: Recommendations follow the numbered list format
output="$($ROOT_DIR/mdoctor diagnose 2>&1)"
# If there are recommendations, they should be numbered (strip ANSI codes first)
if echo "$output" | grep -q "recommendation"; then
  echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -qE '^[0-9]+\.' || fail "Expected numbered recommendations in diagnose output"
fi
pass "diagnose recommendations follow numbered format"

pass "all diagnose tests passed"
