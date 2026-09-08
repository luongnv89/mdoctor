#!/usr/bin/env bats
#
# test_check_modules.bats
# Task 6.6 (issue #65): per-module check assertions. Every registered
# check module must emit its own step header and at least one parseable
# status line when run in isolation. The old macOS-gated aggregate
# assertion ("Health score" appears) would still pass if 19 of 20 modules
# produced nothing, and never ran on Linux. Here the modules run on every
# platform: hanging/CI-unfriendly probes (ping, nslookup) are neutralized
# hermetically with a sparse PATH farm (same pattern as
# test_check_missing_probes.bats) instead of skipping.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Per-command timeout (seconds) to prevent hangs in CI
_CMD_TIMEOUT=280

_run_lim() {
  # Run a command with timeout; fall back to direct exec if unavailable
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# Hermetic single-module PATH: the suite-wide stubs (docker, apt-get,
# sudo) first, then the sparse farm that shadows every host binary except
# the probes whose absence check modules already degrade on — network
# probes (ping, nslookup), proc scanners (ss, ps) and softwareupdate
# (contacts Apple's update servers; the module's guarded absence path
# reports a status_warn skip). Absence-driven degradation IS this
# project's stubbing pattern for platform tools — the same farm powers
# test_check_missing_probes.bats.
_hermetic_check_path() {
  echo "$ROOT_DIR/tests/helpers/bin:$TEST_TMP/farm"
}

# assert_check_module_output MODULE OUTFILE
# Fails — naming MODULE — when a single-module run produced no step
# header or no parseable (indented) status line. Status helpers emit
# two-space-indented lines; the step header is "➤ [n/m] Title".
assert_check_module_output() {
  local module="$1"
  local outfile="$2"
  if ! grep -q '➤ \[' "$outfile"; then
    fail "check module '${module}' emitted no step header"
  fi
  if ! grep -qE '^  [^ ]' "$outfile"; then
    fail "check module '${module}' emitted no parseable status line"
  fi
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"
  # --- Sparse PATH farm: everything the host offers except the probes
  # that can hang CI (ping/nslookup wait on an unreachable network; ss/ps
  # are excluded to exercise the guarded-skip paths deterministically) ---
  mkdir -p "$TEST_TMP/farm" "$TEST_TMP/home"
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        ping|nslookup|ss|ps|softwareupdate) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  # The farm must stay executable on minimal images (Alpine has no
  # /usr/bin/bash) and on macOS (no GNU timeout): link the essentials
  # from the ambient PATH and fall back to running without timeout.
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

@test "mdoctor checks: every registered module emits a header and a status line" {
  # Enumerate from the live registry (`mdoctor list`), never a hardcoded
  # list — a newly registered check module is covered automatically, and
  # each platform only runs its own applicable modules.
  local mods
  mods="$(./mdoctor list | sed -n '/^Check Modules/,/^Cleanup Modules/p' \
    | grep -E '^    [a-z_]+ +\[[A-Z]+\]' | awk '{print $1}')" || mods=""
  [ -n "$mods" ] || fail "no check modules parsed from 'mdoctor list'"

  local m rc=0
  for m in $mods; do
    rc=0
    PATH="$(_hermetic_check_path)" HOME="$TEST_TMP/home" \
      _run_lim ./mdoctor check -m "$m" >"$TEST_TMP/out_$m.txt" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      tail -n 20 "$TEST_TMP/out_$m.txt" >&2 || true
      fail "check module '${m}' exited $rc (expected 0)"
    fi
    assert_check_module_output "$m" "$TEST_TMP/out_$m.txt"
  done
}

@test "mdoctor checks: assertion names a module that produces no output" {
  # Acceptance criterion 3: a module emitting nothing must fail the suite
  # naming that module. Prove it against an empty run log.
  : >"$TEST_TMP/silent.out"
  local out
  out="$(assert_check_module_output battery "$TEST_TMP/silent.out" 2>&1)" || true
  case "$out" in
    *battery*) pass "$out" ;;
    *) fail "expected assertion failure naming 'battery', got: ${out:-<nothing>}" ;;
  esac
}

@test "mdoctor checks: full run emits the health-score summary without a macOS gate" {
  # The old aggregate assertion ran only on macOS; the sparse farm makes
  # the full run hermetic on Linux too (ping/nslookup degrade to skips).
  local rc=0
  PATH="$(_hermetic_check_path)" HOME="$TEST_TMP/home" \
    _run_lim ./mdoctor check >"$TEST_TMP/full_check.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -n 20 "$TEST_TMP/full_check.out" >&2 || true
    fail "full 'mdoctor check' exited $rc (expected 0)"
  fi
  assert_contains "$TEST_TMP/full_check.out" "Health score"
}
