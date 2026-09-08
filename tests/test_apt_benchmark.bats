#!/usr/bin/env bats
#
# test_apt_benchmark.bats
# Task 7.2 (issue #67, F-TEST-005 part 2 of 4): apt check + benchmark lib.
#
# The apt check never executed (Linux-only source, macOS-gated full run);
# lib/benchmark.sh was likewise never exercised. This lane pins both:
# `check -m apt` emits its header + a parseable status line on the Linux
# lane (stub apt-get, never the real package system), and the benchmark
# helpers compute elapsed/time with the reported units (MB/s, ms, s).
# Full run_benchmark (256MB dd + network) is intentionally not executed:
# unit-level + static-unit pins keep the suite hermetic and fast.
# Bash 3.2 compatible.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  TMPHOME="${HOME}/.mdoctor-test-aptbench.$$.$RANDOM"
  mkdir -p "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "check -m apt emits header and a parseable status line" {
  HOME="$TMPHOME" ./mdoctor check -m apt >"$TMPHOME/apt.out" 2>&1
  assert_contains "$TMPHOME/apt.out" "APT Package Manager"
  grep -qE '^  [^ ]' "$TMPHOME/apt.out" || fail "apt check emitted no parseable status line"
}

@test "benchmark helpers compute elapsed time and report units" {
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/benchmark.sh"
  [ "$(bash -c 'source lib/platform.sh; source lib/common.sh; source lib/benchmark.sh; _bench_elapsed 1 2.5')" = "1.500" ] || fail "expected _bench_elapsed 1 2.5 to be 1.500"
  declare -f run_benchmark >/dev/null || fail "run_benchmark not defined"
  declare -f _bench_time >/dev/null || fail "_bench_time not defined"
  grep -q "MB/s" "$ROOT_DIR/lib/benchmark.sh" || fail "benchmark missing MB/s unit"
  grep -q "ms" "$ROOT_DIR/lib/benchmark.sh" || fail "benchmark missing ms unit"
  _t="$(bash -c 'source lib/platform.sh; source lib/common.sh; source lib/benchmark.sh; _bench_time')"
  [ -n "$_t" ] || fail "_bench_time produced no output"
}
