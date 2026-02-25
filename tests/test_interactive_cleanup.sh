#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-interactive.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

# Use platform-aware trash directory
TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
if is_linux; then
  TRASH_DIR="$TMPHOME/.local/share/Trash/files"
fi
mkdir -p "$TRASH_DIR"
echo "sample" > "$TRASH_DIR/interactive.txt"

cd "$ROOT_DIR"

# Dry-run interactive selection (module 1 = trash) should not delete
printf '1\n' | HOME="$TMPHOME" ./mdoctor clean --interactive >/dev/null 2>&1
assert_file_exists "$TRASH_DIR/interactive.txt"

# Force interactive selection should delete
printf '1\n' | HOME="$TMPHOME" ./mdoctor clean --interactive --force >/dev/null 2>&1
assert_file_not_exists "$TRASH_DIR/interactive.txt"

# Invalid selection should fail
set +e
printf '99\n' | HOME="$TMPHOME" ./mdoctor clean --interactive >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected non-zero exit for invalid interactive selection"

pass "interactive cleanup selection"
