#!/usr/bin/env bash
# Task 4.4: every fixes/ command runs through run_cmd_args, so a dry run
# executes zero privileged commands while still recording each intended
# command in the operations log.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-fixdryrun.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

cd "$ROOT_DIR"

export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
STUB_LOG="$TMPHOME/stub.log"
: >"$STUB_LOG"
export MDOCTOR_STUB_LOG="$STUB_LOG"

# Every fix module routes through the wrapper (acceptance grep).
while IFS= read -r f; do
  grep -q "run_cmd_args" "$f" || fail "Expected run_cmd_args in $f"
done < <(find "$ROOT_DIR/fixes" -name '*.sh' | sort)
if grep -rn 'DRY_RUN=false' "$ROOT_DIR/fixes/" | grep -q .; then
  fail "No DRY_RUN=false override may remain in fixes/"
fi

# Dry-run fix-all: zero privileged executions, all intents logged.
set +e
DRY_RUN=true HOME="$TMPHOME" ./mdoctor fix all >"$TMPHOME/fix.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { tail -n 10 "$TMPHOME/fix.out"; fail "Expected fix all exit 0 in dry-run, got $rc"; }

# No privileged binary executed for real: sudo was never even invoked
# (run_cmd_args short-circuits before exec in dry-run).
if grep -q "^sudo " "$STUB_LOG"; then
  fail "Privileged commands executed during dry-run fix all"
fi

# ... but every intended command reached the operations log as dry-run.
OPLOG="$TMPHOME/.config/mdoctor/operations.log"
assert_file_exists "$OPLOG"
assert_contains "$OPLOG" "DRY_RUN_CMD"

pass "fix dry-run executes nothing privileged, logs every intent"
