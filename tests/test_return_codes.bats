#!/usr/bin/env bats
#
# Regression test for Task 9.3 (#84):
#   one return-code contract — no `|| true` on deletion paths, per-module
#   accumulators with taxonomy rendering, blocked-means-nonzero, cmd_check
#   capture, and the documented contract.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup() {
  cd "$ROOT_DIR" || return 1
  export MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DEBUG=false
  BOLD=""; RESET=""
  export BOLD RESET
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  source "$ROOT_DIR/lib/safety.sh"
  source "$ROOT_DIR/lib/cleanup_scope.sh"
  init_colors >/dev/null 2>&1 || true
}

@test "no deletion swallowing survives in cleanups/" {
  hits=$(find "$ROOT_DIR/cleanups" -name '*.sh' | xargs grep -l '|| true' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "every cleanup module accumulates and returns its code" {
  missing=$(find "$ROOT_DIR/cleanups" -name '*.sh' | while read -r f; do
    grep -q 'local rc=0' "$f" || echo "$f(no-accumulator)"
    grep -q 'return "$rc"' "$f" || echo "$f(no-return)"
  done)
  [ -z "$missing" ]
}

@test "crash_reports where every target is blocked exits non-zero" {
  # Force mode (the acceptance scenario runs --force): dry-run maps every
  # policy block to an expected skip instead.
  DRY_RUN=false
  mkdir -p "$HOME/crash/a" "$HOME/crash/b"
  echo x > "$HOME/crash/a/old.crash"
  touch -d "30 days ago" "$HOME/crash/a/old.crash" 2>/dev/null || true
  # Deterministic block: every deletion path is out of scope.
  validate_deletion_path() { return 22; }
  source "$ROOT_DIR/cleanups/crash_reports.sh"
  # Point the module at existing-but-blocked dirs.
  platform_crash_dirs() { printf '%s\n' "$HOME/crash/a" "$HOME/crash/b"; }
  run clean_crash_reports
  [ "$status" -eq 22 ]
  [[ "$output" == *"blocked"* ]]
}

@test "crash_reports with absent targets succeeds quietly" {
  platform_crash_dirs() { printf '%s\n' "$HOME/does-not-exist"; }
  source "$ROOT_DIR/cleanups/crash_reports.sh"
  run clean_crash_reports
  [ "$status" -eq 0 ]
}

@test "cmd_check captures module and doctor exit codes" {
  grep -q '_check_rc=$?' "$ROOT_DIR/mdoctor"
  grep -q 'return "$_check_rc"' "$ROOT_DIR/mdoctor"
  grep -q '_doctor_rc' "$ROOT_DIR/mdoctor"
}

@test "the single return-code contract is documented" {
  grep -q "Return-Code Contract" "$ROOT_DIR/CONTRIBUTING.md"
  grep -q "|| rc=\$?" "$ROOT_DIR/CONTRIBUTING.md"
}
