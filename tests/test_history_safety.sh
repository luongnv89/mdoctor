#!/usr/bin/env bash
# Task 3.4: history fields are validated before arithmetic; state files
# are created private (0700 dirs, 0600 files).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-history.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

cd "$ROOT_DIR"

CANARY="$TMPHOME/mdoctor_canary_$$"
rm -f "$CANARY"

# Poisoned history entry: score is an arithmetic-injection payload.
mkdir -p "$TMPHOME/.mdoctor/history"
cat >"$TMPHOME/.mdoctor/history/20000101_000000.json" <<EOF
{"timestamp":"2000-01-01T00:00:00Z","score":a[\$(touch $CANARY)],"rating":"good","warnings":0,"failures":0}
EOF

HOME="$TMPHOME" ./mdoctor history >"$TMPHOME/history.out" 2>"$TMPHOME/history.err" || true
assert_file_not_exists "$CANARY"
assert_contains "$TMPHOME/history.err" "invalid score"

# Fresh state run creates private dirs/files: config dir 0700, op log 0600.
# (A dry-run clean writes state — oplog, whitelist, scope — without deleting.)
rm -rf "$TMPHOME/.config" "$TMPHOME/.mdoctor"
HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
[ "$(stat -c %a "$TMPHOME/.config/mdoctor")" = "700" ] || fail "Expected 0700 on config dir"
[ "$(stat -c %a "$TMPHOME/.config/mdoctor/operations.log")" = "600" ] || fail "Expected 0600 on operations log"

pass "history validation + private state modes"
