#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

cd "$ROOT_DIR"

./mdoctor list >"$TMPDIR_TEST/list.txt" 2>&1

# Check modules present
assert_contains "$TMPDIR_TEST/list.txt" "battery"
assert_contains "$TMPDIR_TEST/list.txt" "network"
assert_contains "$TMPDIR_TEST/list.txt" "containers"

# Cleanup modules present
assert_contains "$TMPDIR_TEST/list.txt" "trash"
assert_contains "$TMPDIR_TEST/list.txt" "dev_caches"

# Fix targets present
assert_contains "$TMPDIR_TEST/list.txt" "homebrew"
assert_contains "$TMPDIR_TEST/list.txt" "spotlight"

pass "metadata routing/list coverage"
