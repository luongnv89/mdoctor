#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPHOME="$(mktemp -d)"
trap 'rm -rf "$TMPHOME"' EXIT

mkdir -p "$TMPHOME/.Trash"
echo "sample" > "$TMPHOME/.Trash/sample.txt"

cd "$ROOT_DIR"

# Dry-run should not delete
HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
assert_file_exists "$TMPHOME/.Trash/sample.txt"

# Force should delete (no whitelist)
mkdir -p "$TMPHOME/.config/mdoctor"
cat > "$TMPHOME/.config/mdoctor/cleanup_whitelist" <<EOF
# empty
EOF
HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
assert_file_not_exists "$TMPHOME/.Trash/sample.txt"

pass "dry-run vs force semantics"
