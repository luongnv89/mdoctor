#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

ORIG_HOME="${HOME}"
TMPHOME="$(mktemp -d "${ORIG_HOME}/.mdoctor-test-safety.XXXXXX")"
trap 'rm -rf "$TMPHOME"' EXIT

export HOME="$TMPHOME"
export MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPHOME/.config/mdoctor/cleanup_whitelist"
mkdir -p "$TMPHOME/.config/mdoctor"

cd "$ROOT_DIR"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/safety.sh"

set +e
validate_deletion_path "/" >/dev/null 2>&1
rc_root=$?
validate_deletion_path "relative/path" >/dev/null 2>&1
rc_rel=$?
set -e

[ "$rc_root" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '/'"
[ "$rc_rel" -eq "$MDOCTOR_SAFE_ERR_INVALID_TARGET" ] || fail "Expected invalid-target code for relative path"

mkdir -p "$TMPHOME/safe"
echo "data" > "$TMPHOME/safe/file.txt"
ln -s "$TMPHOME/safe/file.txt" "$TMPHOME/safe/link.txt"

set +e
safe_remove "$TMPHOME/safe/link.txt" >/dev/null 2>&1
rc_link=$?
set -e
[ "$rc_link" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code"

# Whitelist exact directory and ensure descendant is protected
cat > "$MDOCTOR_CLEANUP_WHITELIST_FILE" <<EOF
~/.Trash
EOF
_MDOCTOR_WHITELIST_LOADED=false
mkdir -p "$TMPHOME/.Trash"
echo "keep" > "$TMPHOME/.Trash/protect.txt"

DRY_RUN=false
safe_remove "$TMPHOME/.Trash/protect.txt" >/dev/null 2>&1 || true
assert_file_exists "$TMPHOME/.Trash/protect.txt"

pass "safety validation + whitelist protection"
