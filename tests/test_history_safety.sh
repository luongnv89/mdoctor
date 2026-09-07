#!/usr/bin/env bash
# Task 3.4: history fields are validated before arithmetic; state files
# are created private (0700 dirs, 0600 files).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

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

# Portable file-mode query, gated on the platform predicates (a blind
# BSD-then-GNU fallback misfires: GNU stat -f means --filesystem and
# prints garbage to stdout while still failing).
file_mode() {
  if is_macos; then
    stat -f "%Lp" "$1" 2>/dev/null || echo ""
  else
    stat -c "%a" "$1" 2>/dev/null || echo ""
  fi
}

# Fresh state run creates private dirs/files: config dir 0700, op log 0600.
# (A dry-run clean writes state — oplog, whitelist, scope — without deleting.)
rm -rf "$TMPHOME/.config" "$TMPHOME/.mdoctor"
HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
[ "$(file_mode "$TMPHOME/.config/mdoctor")" = "700" ] || fail "Expected 0700 on config dir"
[ "$(file_mode "$TMPHOME/.config/mdoctor/operations.log")" = "600" ] || fail "Expected 0600 on operations log"
[ "$(file_mode "$TMPHOME/.config/mdoctor/cleanup_scope.conf")" = "600" ] || fail "Expected 0600 on scope file"
[ "$(file_mode "$TMPHOME/.config/mdoctor/cleanup_whitelist")" = "600" ] || fail "Expected 0600 on whitelist file"

# Task 4.7: an unreadable history file is skipped, never retried forever.
# (Before the fix, `|| continue` skipped the index increment and the same
# entry was retried indefinitely.)
mkdir -p "$TMPHOME/.mdoctor/history"
echo '{"timestamp":"2026-09-01T00:00:00Z","score":80,"rating":"Good","warnings":1,"failures":0}' >"$TMPHOME/.mdoctor/history/20260901_000000.json"
echo '{"timestamp":"2026-09-02T00:00:00Z","score":85,"rating":"Good","warnings":0,"failures":0}' >"$TMPHOME/.mdoctor/history/20260902_000000.json"
chmod 000 "$TMPHOME/.mdoctor/history/20260901_000000.json"
set +e
if command -v timeout >/dev/null 2>&1; then
  HOME="$TMPHOME" timeout 10 ./mdoctor history >"$TMPHOME/history2.out" 2>"$TMPHOME/history2.err"
else
  HOME="$TMPHOME" ./mdoctor history >"$TMPHOME/history2.out" 2>"$TMPHOME/history2.err"
fi
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "history hung or failed on an unreadable entry (rc=$rc)"
chmod 644 "$TMPHOME/.mdoctor/history/20260901_000000.json"

pass "history validation + private state modes"
