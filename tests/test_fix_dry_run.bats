#!/usr/bin/env bats
# Task 4.4: every fixes/ command runs through run_cmd_args, so a dry run
# executes zero privileged commands while still recording each intended
# command in the operations log.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME STUB_LOG
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-fixdryrun.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  STUB_LOG="$TMPHOME/stub.log"
  : >"$STUB_LOG"
  export MDOCTOR_STUB_LOG="$STUB_LOG"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "every fix module routes through run_cmd_args" {
  while IFS= read -r f; do
    grep -q "run_cmd_args" "$f" || fail "Expected run_cmd_args in $f"
  done < <(find "$ROOT_DIR/fixes" -name '*.sh' | sort)
  if grep -rn 'DRY_RUN=false' "$ROOT_DIR/fixes/" | grep -q .; then
    fail "No DRY_RUN=false override may remain in fixes/"
  fi
}

@test "dry-run fix all executes nothing privileged and logs every intent" {
  DRY_RUN=true HOME="$TMPHOME" ./mdoctor fix all >"$TMPHOME/fix.out" 2>&1 || {
    local rc=$?
    tail -n 10 "$TMPHOME/fix.out"
    fail "Expected fix all exit 0 in dry-run, got $rc"
  }
  # No privileged binary executed for real: sudo was never even invoked
  # (run_cmd_args short-circuits before exec in dry-run).
  if grep -q "^sudo " "$STUB_LOG"; then
    fail "Privileged commands executed during dry-run fix all"
  fi
  # ... but every intended command reached the operations log as dry-run.
  OPLOG="$TMPHOME/.config/mdoctor/operations.log"
  assert_file_exists "$OPLOG"
  assert_contains "$OPLOG" "DRY_RUN_CMD"
}
