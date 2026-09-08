#!/usr/bin/env bats
# Task 4.3: temp files come from mktemp under a per-user 0700 dir — a
# stale file planted at an old predictable path is never touched.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/common.sh"

# Portable file-mode query, gated on the platform predicates (BSD stat
# has no -c flag; GNU stat -f means --filesystem).
if is_macos; then
  file_mode() { stat -f "%Lp" "$1" 2>/dev/null || echo ""; }
else
  file_mode() { stat -c "%a" "$1" 2>/dev/null || echo ""; }
fi

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "helpers land under a 0700 per-user dir" {
  dir="$(mdoctor_tmpdir)"
  [ -d "$dir" ] || fail "Expected tmpdir to exist"
  [ "$(file_mode "$dir")" = "700" ] || fail "Expected 0700 on tmpdir"
  f="$(mdoctor_mktemp_file probe)"
  [ -f "$f" ] || fail "Expected mktemp file to exist"
  rm -f "$f"
}

@test "hostile stale file at the old predictable path is untouched" {
  printf 'HOSTILE' > /tmp/docker_info.log
  ./mdoctor check -m devtools >/dev/null 2>&1 || true
  [ "$(cat /tmp/docker_info.log 2>/dev/null)" = "HOSTILE" ] || fail "Planted /tmp/docker_info.log was touched"
  rm -f /tmp/docker_info.log
}
