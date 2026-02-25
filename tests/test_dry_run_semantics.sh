#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-dryrun.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

# Use platform-aware trash directory
TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
if is_linux; then
  TRASH_DIR="$TMPHOME/.local/share/Trash/files"
fi
mkdir -p "$TRASH_DIR"
echo "sample" > "$TRASH_DIR/sample.txt"

cd "$ROOT_DIR"

# Dry-run should not delete
HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
assert_file_exists "$TRASH_DIR/sample.txt"

# Force should delete (no whitelist)
mkdir -p "$TMPHOME/.config/mdoctor"
cat > "$TMPHOME/.config/mdoctor/cleanup_whitelist" <<EOF
# empty
EOF
HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
assert_file_not_exists "$TRASH_DIR/sample.txt"

pass "dry-run vs force semantics"
