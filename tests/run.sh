#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hermetic suite (Task 0.1): shadow `docker`, `apt-get` and `sudo` with
# stubs that record argv instead of reaching a real daemon or the package
# system, so no test file can destroy external state. Individual tests may
# set MDOCTOR_STUB_LOG to a file to assert on intercepted invocations.
export PATH="$SCRIPT_DIR/helpers/bin:$PATH"

TEST_FILES=("$SCRIPT_DIR"/test_*.sh)
if [ ! -e "${TEST_FILES[0]}" ]; then
  echo "No test files found in $SCRIPT_DIR"
  exit 1
fi

pass_count=0
fail_count=0

for test_file in "${TEST_FILES[@]}"; do
  echo
  echo "== Running $(basename "$test_file") =="
  if bash "$test_file"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
done

echo
printf "Test summary: %d passed, %d failed\n" "$pass_count" "$fail_count"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
