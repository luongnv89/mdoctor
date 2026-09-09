#!/usr/bin/env bats
#
# Regression test for issue #9:
#   `mdoctor clean -f` exited silently after the pre-flight summary when a
#   target path caused `du` to fail (e.g. permission errors on items inside
#   ~/.Trash on macOS). Under `set -euo pipefail` the failing pipeline aborted
#   the script before any "Touched targets:" entries were printed.
#
# This test poisons one of the preflight target paths so `du` exits non-zero,
# then verifies the script still completes the preflight summary without
# silently exiting.
#
# Scope: this test only exercises the preflight summary in `cleanup.sh`. The
# same `du -sk ... | awk` pattern exists in several cleanup-phase modules
# (cleanups/xcode.sh, cleanups/dev_caches.sh, cleanups/ios_backups.sh,
# checks/storage.sh) and is similarly vulnerable. A follow-up issue tracks
# hardening those sites; this test does not cover them.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME TRASH_DIR STUB_LOG
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-preflight.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  # Build a poisoned trash dir: contains a subdirectory with no read/exec
  # perms, which is exactly what `du -sk` chokes on (per-item permission
  # denied).
  TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
  if is_linux; then
    TRASH_DIR="$TMPHOME/.local/share/Trash/files"
  fi
  mkdir -p "$TRASH_DIR/poisoned"
  echo "data" > "$TRASH_DIR/poisoned/file.txt"
  chmod 000 "$TRASH_DIR/poisoned"
  STUB_LOG="$TMPHOME/stub.log"
  : >"$STUB_LOG"
}

teardown_file() {
  # Restore permissions so cleanup can succeed even if a poisoned dir
  # was made.
  if [ -d "$TMPHOME" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "force-mode preflight is resilient to du permission errors (issue #9)" {
  # Run preflight in force mode but stop before destructive execution (Task
  # 0.1): MDOCTOR_PREFLIGHT_ONLY exits right after the summary, so this test
  # asserts on preflight output alone and never reaches a real daemon.
  # Capture stdout+stderr; allow non-zero exit (we assert on output content).
  local out_file="$TMPHOME/preflight.out"
  MDOCTOR_STUB_LOG="$STUB_LOG" MDOCTOR_PREFLIGHT_ONLY=true \
    HOME="$TMPHOME" ./cleanup.sh --force >"$out_file" 2>&1 || true

  # Restore perms so teardown can clean up.
  chmod -R u+rwx "$TMPHOME" 2>/dev/null || true

  # Assert: pre-flight summary header was printed.
  assert_contains "$out_file" "Pre-flight Safety Summary"

  # Assert: at least one target line was printed (the bug from #9 produced
  # an empty "Touched targets:" block followed by an immediate silent exit).
  grep -q '^  - ' "$out_file" \
    || fail "preflight emitted no '  - <path>' target lines (issue #9 regression)"

  # Assert: the estimated-reclaim footer was printed, proving the preflight
  # function ran to completion instead of aborting mid-loop.
  assert_contains "$out_file" "Estimated reclaim size:"

  # Assert: pre-flight-only mode stopped before destructive execution.
  assert_contains "$out_file" "Pre-flight only"

  # Assert: no real destructive path was reached — the stub log must not
  # contain a `docker system prune` invocation (the stubs on PATH would
  # have recorded it instead of reaching a daemon).
  assert_not_contains "$STUB_LOG" "docker system prune"

  # Assert: the stubs actually intercept (a direct prune call is recorded,
  # not executed, and exits 0).
  MDOCTOR_STUB_LOG="$STUB_LOG" docker system prune -af --volumes >/dev/null 2>&1
  assert_contains "$STUB_LOG" "docker system prune -af --volumes"
  MDOCTOR_STUB_LOG="$STUB_LOG" sudo apt-get autoremove -y >/dev/null 2>&1
  assert_contains "$STUB_LOG" "apt-get autoremove -y"
}
