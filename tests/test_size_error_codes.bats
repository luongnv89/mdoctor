#!/usr/bin/env bats
#
# Regression test for Task 9.4 (issue #85):
# the directory-size helpers print only on success and return a distinct
# non-zero code per failure mode, so "not a directory", "timed out",
# "permission denied" and a genuine measurement are no longer
# indistinguishable.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  export TMPHOME OK_DIR DENIED_DIR
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-sizecodes.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  OK_DIR="$TMPHOME/ok"
  mkdir -p "$OK_DIR"
  echo "data" > "$OK_DIR/file.txt"
  DENIED_DIR="$TMPHOME/denied"
  mkdir -p "$DENIED_DIR"
  echo "data" > "$DENIED_DIR/file.txt"
  chmod 000 "$DENIED_DIR"
}

teardown_file() {
  if [ -d "${TMPHOME:-}" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "genuine measurement: rc 0, numeric stdout" {
  source "$ROOT_DIR/lib/disk.sh"
  out=$(du_size_kb "$OK_DIR"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
  [ "$out" -gt 0 ]
  out=$(du_size_kb "$OK_DIR/file.txt"); rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
}

@test "not a directory: MDOCTOR_SIZE_ERR_NO_TARGET" {
  source "$ROOT_DIR/lib/disk.sh"
  out=""; rc=0
  out=$(du_size_kb "$TMPHOME/does-not-exist") || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NO_TARGET" ]
  [ -z "$out" ]
  out=""; rc=0
  out=$(du_size_kb "") || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NO_TARGET" ]
  [ -z "$out" ]
}

@test "permission denied: MDOCTOR_SIZE_ERR_DENIED" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root bypasses mode checks"
  fi
  source "$ROOT_DIR/lib/disk.sh"
  out=""; rc=0
  out=$(du_size_kb "$DENIED_DIR") || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_DENIED" ]
  [ -z "$out" ]
}

@test "timed out: MDOCTOR_SIZE_ERR_TIMEOUT" {
  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout(1) not available"
  fi
  source "$ROOT_DIR/lib/disk.sh"
  STUBBIN="$TMPHOME/stubbin"
  mkdir -p "$STUBBIN"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$STUBBIN/du"
  chmod +x "$STUBBIN/du"
  out=""; rc=0
  out=$(PATH="$STUBBIN:$PATH" MDOCTOR_DU_TIMEOUT_S=1 du_size_kb "$OK_DIR") || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_TIMEOUT" ]
  [ -z "$out" ]
}

@test "preflight find preserves missing and timeout errors" {
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"

  out=""; rc=0
  out=$(preflight_find_kb "$TMPHOME/does-not-exist" -type f) || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NO_TARGET" ]
  [ -z "$out" ]

  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout(1) not available"
  fi
  STUBBIN="$TMPHOME/preflight-stubbin"
  mkdir -p "$STUBBIN"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$STUBBIN/find"
  chmod +x "$STUBBIN/find"
  out=""; rc=0
  out=$(PATH="$STUBBIN:$PATH" MDOCTOR_FIND_TIMEOUT_S=1 preflight_find_kb "$OK_DIR" -type f) || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_TIMEOUT" ]
  [ -z "$out" ]

  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBBIN/find"
  chmod +x "$STUBBIN/find"
  out=""; rc=0
  out=$(PATH="$STUBBIN:$PATH" preflight_find_kb "$OK_DIR" -type f) || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_DENIED" ]
  [ -z "$out" ]

  EMPTY_DIR="$TMPHOME/empty"
  mkdir -p "$EMPTY_DIR"
  out=$(preflight_find_kb "$EMPTY_DIR" -type f); rc=$?
  [ "$rc" -eq 0 ]
  [ "$out" = 0 ]
}

@test "check-module wrapper propagates: _dir_size_kb" {
  source "$ROOT_DIR/lib/context.sh"
  mdoctor_context_init
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/checks/storage.sh"
  out=""; rc=0
  out=$(_dir_size_kb "$TMPHOME/does-not-exist") || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NO_TARGET" ]
  [ -z "$out" ]
  out=""; rc=0
  out=$(_dir_size_kb "$OK_DIR") || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$out" =~ ^[0-9]+$ ]]
}
