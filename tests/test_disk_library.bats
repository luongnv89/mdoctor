#!/usr/bin/env bats
#
# Regression test for Task 8.2 (#76):
#   one size-formatter ladder, one hardened du probe, one timestamp function.
# - format_size_kb is the single ladder; kb_to_human/human_readable_kb agree
# - du_size_kb always prints a number and exits 0 (even on unreadable paths)
# - no `du -sk` call site survives outside lib/disk.sh
# - no awk GB/MB formatter ladder survives outside lib/disk.sh
# - timestamp and oplog_timestamp agree (one implementation)
# - single-module pre-flight with a permission-denied subdirectory completes
#   with a numeric estimate under both cleanup.sh and mdoctor (no abort)

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME POISONED
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-disklib.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  POISONED="$TMPHOME/poisoned"
  mkdir -p "$POISONED/sub"
  echo "data" > "$POISONED/sub/file.txt"
  chmod 000 "$POISONED/sub"
}

teardown_file() {
  if [ -d "${TMPHOME:-}" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "one formatter ladder: wrappers agree with format_size_kb" {
  source "$ROOT_DIR/lib/disk.sh"
  [ "$(format_size_kb 512)" = "512 KB" ]
  [ "$(format_size_kb 2048)" = "2.00 MB" ]
  [ "$(format_size_kb 2097152)" = "2.00 GB" ]
  [ "$(kb_to_human 2097152)" = "$(format_size_kb 2097152)" ]
  [ "$(human_readable_kb 2048)" = "$(format_size_kb 2048)" ]
  [ "$(human_readable_kb -2048)" = "$(format_size_kb 2048)" ]
}

@test "du_size_kb always prints a number and exits 0" {
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/disk.sh"
  out=$(du_size_kb "$POISONED/sub"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
  [ "$(du_size_kb /nonexistent-path-xyz)" = "0" ]
  out=$(du_size_kb "$POISONED/sub/file.txt"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
}

@test "no du call site survives outside lib/disk.sh" {
  # BusyBox-grep compatible: no grep --include.
  hits=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" -not -path "$ROOT_DIR/lib/disk.sh" | xargs grep -l 'du -sk' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "no awk GB/MB formatter ladder survives outside lib/disk.sh" {
  hits=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" -not -path "$ROOT_DIR/lib/disk.sh" | xargs grep -l 'awk.*printf.*[GM]B' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "timestamp and oplog_timestamp agree" {
  source "$ROOT_DIR/lib/logging.sh"
  [ "$(oplog_timestamp)" = "$(timestamp)" ]
}

@test "cleanup.sh force preflight completes with poisoned subdir" {
  export HOME="$TMPHOME"
  export MDOCTOR_PREFLIGHT_ONLY=true
  run "$ROOT_DIR/cleanup.sh" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Estimated reclaim size:"* ]]
}

@test "mdoctor single-module preflight completes with poisoned trash" {
  export HOME="$TMPHOME"
  mkdir -p "$TMPHOME/.local/share/Trash/files/poisoned"
  echo "data" > "$TMPHOME/.local/share/Trash/files/poisoned/file.txt"
  chmod 000 "$TMPHOME/.local/share/Trash/files/poisoned"
  out=$(printf 'n\n' | "$ROOT_DIR/mdoctor" clean -m trash --force 2>&1 || true)
  [[ "$out" == *"Pre-flight Safety Summary"* ]]
  [[ "$out" == *"(~"* ]]
  chmod -R u+rwx "$TMPHOME/.local/share/Trash" 2>/dev/null || true
}
