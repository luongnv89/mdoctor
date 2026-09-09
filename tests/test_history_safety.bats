#!/usr/bin/env bats
# Task 3.4: history fields are validated before arithmetic; state files
# are created private (0700 dirs, 0600 files).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

# Portable file-mode query: GNU stat -c first (Linux, and macOS when
# coreutils is installed), BSD stat -f fallback. GNU stat -f means
# --filesystem, so -f must never be tried first.
file_mode() {
  stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1" 2>/dev/null || echo ""
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME CANARY
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-history.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  CANARY="$TMPHOME/mdoctor_canary_$$"
  rm -f "$CANARY"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "poisoned history score is rejected without arithmetic evaluation" {
  mkdir -p "$TMPHOME/.mdoctor/history"
  cat >"$TMPHOME/.mdoctor/history/20000101_000000.json" <<EOF
{"timestamp":"2000-01-01T00:00:00Z","score":a[\$(touch $CANARY)],"rating":"good","warnings":0,"failures":0}
EOF
  HOME="$TMPHOME" ./mdoctor history >"$TMPHOME/history.out" 2>"$TMPHOME/history.err" || true
  assert_file_not_exists "$CANARY"
  assert_contains "$TMPHOME/history.err" "invalid score"
}

@test "fresh state run creates private dirs and files" {
  rm -rf "$TMPHOME/.config" "$TMPHOME/.mdoctor"
  HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
  [ "$(file_mode "$TMPHOME/.config/mdoctor")" = "700" ] || fail "Expected 0700 on config dir, got: [$(file_mode "$TMPHOME/.config/mdoctor")] platform=${MDOCTOR_PLATFORM:-unset}"
  [ "$(file_mode "$TMPHOME/.config/mdoctor/operations.log")" = "600" ] || fail "Expected 0600 on operations log"
  [ "$(file_mode "$TMPHOME/.config/mdoctor/cleanup_scope.conf")" = "600" ] || fail "Expected 0600 on scope file"
  [ "$(file_mode "$TMPHOME/.config/mdoctor/cleanup_whitelist")" = "600" ] || fail "Expected 0600 on whitelist file"
}

@test "unreadable history entry is skipped, never retried forever" {
  # Task 4.7: before the fix, `|| continue` skipped the index increment
  # and the same entry was retried indefinitely.
  mkdir -p "$TMPHOME/.mdoctor/history"
  echo '{"timestamp":"2026-09-01T00:00:00Z","score":80,"rating":"Good","warnings":1,"failures":0}' >"$TMPHOME/.mdoctor/history/20260901_000000.json"
  echo '{"timestamp":"2026-09-02T00:00:00Z","score":85,"rating":"Good","warnings":0,"failures":0}' >"$TMPHOME/.mdoctor/history/20260902_000000.json"
  chmod 000 "$TMPHOME/.mdoctor/history/20260901_000000.json"
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    HOME="$TMPHOME" timeout 10 ./mdoctor history >"$TMPHOME/history2.out" 2>"$TMPHOME/history2.err" || rc=$?
  else
    HOME="$TMPHOME" ./mdoctor history >"$TMPHOME/history2.out" 2>"$TMPHOME/history2.err" || rc=$?
  fi
  [ "$rc" -eq 0 ] || fail "history hung or failed on an unreadable entry (rc=$rc)"
  chmod 644 "$TMPHOME/.mdoctor/history/20260901_000000.json"
}
