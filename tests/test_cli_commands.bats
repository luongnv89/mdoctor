#!/usr/bin/env bats
#
# test_cli_commands.bats
# Task 7.3 (issue #68, F-TEST-005 part 3 of 4): the two untested CLI cmds.
#
# `mdoctor benchmark` and `mdoctor update` had neither exit-status nor
# output coverage. This lane pins both with exit status + content:
# benchmark runs against instant nslookup/curl stubs (disk + gzip real,
# <2s) and must exit 0 printing the summary units; update --help,
# bad-channel and URL-remote rejections assert status + message with
# zero network (all fail before any fetch).
# Bash 3.2 compatible.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-clicmds.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  mkdir -p "$TMPHOME/stubbin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPHOME/stubbin/nslookup"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPHOME/stubbin/curl"
  chmod +x "$TMPHOME/stubbin/nslookup" "$TMPHOME/stubbin/curl"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "benchmark exits 0 and prints the results summary with units" {
  local rc=0
  PATH="$TMPHOME/stubbin:$PATH" ./mdoctor benchmark >"$TMPHOME/bench.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "expected mdoctor benchmark exit 0, got $rc"
  assert_contains "$TMPHOME/bench.out" "System Benchmark"
  assert_contains "$TMPHOME/bench.out" "MB/s"
}

@test "update --help exits 0 with usage" {
  local rc=0
  ./mdoctor update --help >"$TMPHOME/update-help.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "expected update --help exit 0, got $rc"
  assert_contains "$TMPHOME/update-help.out" "Usage: mdoctor update"
}

@test "update rejects bad channel and URL remote before any fetch" {
  local rc=0
  ./mdoctor update --channel bogus >"$TMPHOME/update-bad.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for bad channel"
  assert_contains "$TMPHOME/update-bad.out" "Unsupported update channel"
  rc=0
  MDOCTOR_UPDATE_REMOTE="https://example.com/x.git" ./mdoctor update --check >"$TMPHOME/update-url.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for URL remote"
  assert_contains "$TMPHOME/update-url.out" "not a URL"
}
