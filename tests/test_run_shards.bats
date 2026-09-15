#!/usr/bin/env bats
#
# test_run_shards.bats — issue #206
#
# The macOS CI leg shards the suite with `tests/run.sh --shard I/N`
# (round-robin over the resolved file list) instead of running every
# test_*.bats serially on one runner. These tests pin the partition
# contract the workflow relies on:
#
#   * `--shard I/N` keeps exactly the files whose 1-based position p in
#     the resolved list satisfies (p - I) % N == 0;
#   * the N shards are pairwise disjoint and their union is the whole
#     suite — no file is dropped or double-run;
#   * malformed specs exit non-zero instead of silently running
#     everything;
#   * `--list` resolves the list (glob + shard) without provisioning or
#     running bats, so it doubles as the CI/debug view.
#
# All assertions run through `--list`, so this file is fast on every
# lane and needs no bats-core provision beyond the suite's own.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-shards.$(fixture_run_id).XXXXXX")"
  export TEST_TMP
  fixture_trap_cleanup "$TEST_TMP"

  # Full resolved list — the runner's own --list output is the reference,
  # so the assertion tracks suite growth automatically.
  ./tests/run.sh --list | LC_ALL=C sort >"$TEST_TMP/all.txt"
  [ -s "$TEST_TMP/all.txt" ] || fail "run.sh --list produced no files"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

# _shard_list I N — resolved file list for shard I of N.
_shard_list() {
  ./tests/run.sh --shard "$1/$2" --list
}

@test "run.sh --list prints every tests/test_*.bats file" {
  local expected
  expected="$(cd "$ROOT_DIR" && ls tests/test_*.bats | LC_ALL=C sort | sed "s|^|$ROOT_DIR/|")"
  [ "$(cat "$TEST_TMP/all.txt")" = "$expected" ]
}

@test "--shard 1/1 is a no-op returning the full list" {
  _shard_list 1 1 | LC_ALL=C sort >"$TEST_TMP/s11.txt"
  cmp -s "$TEST_TMP/s11.txt" "$TEST_TMP/all.txt" \
    || fail "--shard 1/1 differs from the full list"
}

@test "two shards are disjoint and union to the full suite" {
  _shard_list 1 2 | LC_ALL=C sort >"$TEST_TMP/s12.txt"
  _shard_list 2 2 | LC_ALL=C sort >"$TEST_TMP/s22.txt"
  [ -s "$TEST_TMP/s12.txt" ] || fail "shard 1/2 resolved empty"
  [ -s "$TEST_TMP/s22.txt" ] || fail "shard 2/2 resolved empty"

  # Disjoint: no basename appears in both shards.
  local dupes
  dupes="$(cat "$TEST_TMP/s12.txt" "$TEST_TMP/s22.txt" | LC_ALL=C sort | uniq -d)"
  [ -z "$dupes" ] || fail "files in both shards: $dupes"

  # Complete: union equals the full resolved list.
  cat "$TEST_TMP/s12.txt" "$TEST_TMP/s22.txt" | LC_ALL=C sort >"$TEST_TMP/union2.txt"
  cmp -s "$TEST_TMP/union2.txt" "$TEST_TMP/all.txt" \
    || fail "shard union does not cover the full suite"
}

@test "shard split is round-robin over the resolved list" {
  _shard_list 1 3 >"$TEST_TMP/s13.txt"
  _shard_list 2 3 >"$TEST_TMP/s23.txt"
  _shard_list 3 3 >"$TEST_TMP/s33.txt"

  # Reconstruct expectations from the unsharded order: position p
  # (1-based) belongs to shard I when (p - I) % 3 == 0, i.e. shard 1 gets
  # NR≡1 (mod 3), shard 2 gets NR≡2, shard 3 gets NR≡0. Both sides stay
  # in resolved order — sorting would hide a misordered partition.
  awk 'NR % 3 == 1' < <(./tests/run.sh --list) >"$TEST_TMP/want1.txt"
  awk 'NR % 3 == 2' < <(./tests/run.sh --list) >"$TEST_TMP/want2.txt"
  awk 'NR % 3 == 0' < <(./tests/run.sh --list) >"$TEST_TMP/want3.txt"

  cmp -s "$TEST_TMP/s13.txt" "$TEST_TMP/want1.txt" || fail "shard 1/3 is not round-robin"
  cmp -s "$TEST_TMP/s23.txt" "$TEST_TMP/want2.txt" || fail "shard 2/3 is not round-robin"
  cmp -s "$TEST_TMP/s33.txt" "$TEST_TMP/want3.txt" || fail "shard 3/3 is not round-robin"
}

@test "--shard applies to an explicit file list too" {
  local out
  out="$(./tests/run.sh --shard 2/2 --list \
    tests/test_command_parsing.bats \
    tests/test_json_output.bats \
    tests/test_module_list_parity.bats \
    tests/test_shell_expand.bats)"
  # Positions 2 and 4 of the explicit list survive.
  case "$out" in
    *test_json_output.bats*test_shell_expand.bats*) ;;
    *) fail "explicit-list shard kept unexpected files: $out" ;;
  esac
  case "$out" in
    *test_command_parsing.bats*|*test_module_list_parity.bats*)
      fail "explicit-list shard kept a non-member: $out" ;;
  esac
}

@test "malformed --shard specs fail non-zero" {
  local spec
  for spec in "" "0/2" "3/2" "1/0" "x/2" "2/x" "2" "/2" "1/" "1/2/3"; do
    run ./tests/run.sh --shard "$spec" --list
    [ "$status" -ne 0 ] || fail "--shard '$spec' was accepted (status 0)"
  done

  # A bare trailing --shard (no value at all) must error, not spin the
  # arg loop or silently run the full suite on every leg.
  run ./tests/run.sh --shard
  [ "$status" -ne 0 ] || fail "bare --shard was accepted (status 0)"
}

@test "-h/--help documents --shard and --list" {
  run ./tests/run.sh -h
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" >"$TEST_TMP/help.txt"
  assert_contains "$TEST_TMP/help.txt" "--shard"
  assert_contains "$TEST_TMP/help.txt" "--list"
}
