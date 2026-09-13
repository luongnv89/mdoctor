#!/usr/bin/env bats
#
# test_command_badges.bats
# Issue #107 (Task 12.4 — closes F-UX-012, F-UX-013): honest badges and a
# bare-invocation orientation block.
#   * `mdoctor list` shows the diagnose module at a read-only badge — the
#     diagnosis function only reads; [HIGH] ("destructive or hard to
#     reverse") trained users to discount the badge column.
#   * `mdoctor help` renders the same badge in its command table; every
#     command's class (read-only / modifies / deletes) comes from the
#     command registry in lib/registry.sh, and the three classes stay
#     distinguishable in a `cat -v` capture because the marker is literal
#     text, never color alone.
#   * Bare `mdoctor` prints a short orientation block that ends in a
#     recommended first command.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-cmdbadges.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/home"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

setup() {
  export HOME="$TEST_TMP/home"
}

_load_registry() {
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  register_all_modules
}

@test "registry: every top-level command carries a class badge" {
  _load_registry
  local cmd
  for cmd in check clean fix diagnose info list history benchmark update version help; do
    command_risk "$cmd" >/dev/null || fail "command '$cmd' missing from the command registry"
  done
}

@test "registry: badge levels map onto read-only / modifies / deletes" {
  _load_registry
  [ "$(command_class SAFE)" = "read-only" ]
  [ "$(command_class LOW)" = "modifies" ]
  [ "$(command_class MED)" = "modifies" ]
  [ "$(command_class HIGH)" = "deletes" ]
  # F-UX-012: diagnose only reads — it must sit in the read-only class,
  # never at the destructive end.
  [ "$(command_class "$(command_risk diagnose)")" = "read-only" ]
  [ "$(command_class "$(command_risk check)")" = "read-only" ]
  [ "$(command_class "$(command_risk clean)")" = "deletes" ]
}

@test "registry: throwaway command row propagates to the rendered table" {
  _load_registry
  register_command probe_xyz LOW "Throwaway probe command"
  run registry_command_lines
  [[ "$output" == *"probe_xyz"*"[LOW]"*"modifies"* ]]
}

@test "list shows the diagnose module at a read-only badge" {
  ./mdoctor list >"$TEST_TMP/list.out" 2>&1
  local dline
  dline="$(grep 'diagnose' "$TEST_TMP/list.out")"
  case "$dline" in
    *"[SAFE]"*) ;;
    *) fail "diagnose row not badged [SAFE]: $dline" ;;
  esac
  case "$dline" in
    *"[HIGH]"*) fail "diagnose still badged [HIGH]: $dline" ;;
    *) ;;
  esac
}

@test "help renders a class badge on every command-table row" {
  ./mdoctor help >"$TEST_TMP/help.out" 2>&1
  assert_contains "$TEST_TMP/help.out" "Commands:"
  local cmd
  for cmd in check clean fix diagnose info list history benchmark update version help; do
    grep -E "^  ${cmd} +\[(SAFE|LOW|MED|HIGH)\]" "$TEST_TMP/help.out" >/dev/null \
      || fail "no badged row for '$cmd' in the help command table"
  done
  # help and list can never disagree: diagnose is [SAFE] in both.
  grep -E '^  diagnose +\[SAFE\]' "$TEST_TMP/help.out" >/dev/null \
    || fail "diagnose not badged [SAFE] in the help command table"
}

@test "the three classes are distinguishable in a cat -v capture" {
  # The issue's verify step pipes through `cat -v`: the class marker must
  # be literal text so it survives color-stripping. Every row carries the
  # class word next to its badge — one representative per class below.
  ./mdoctor help | cat -v >"$TEST_TMP/help.catv"
  grep -E '^  check +\[SAFE\] +read-only' "$TEST_TMP/help.catv" >/dev/null \
    || fail "read-only class not text-marked on the check row"
  grep -E '^  fix +\[MED\] +modifies' "$TEST_TMP/help.catv" >/dev/null \
    || fail "modifies class not text-marked on the fix row"
  grep -E '^  clean +\[HIGH\] +deletes' "$TEST_TMP/help.catv" >/dev/null \
    || fail "deletes class not text-marked on the clean row"
  # And the badge→class legend names all three classes in plain text.
  assert_contains "$TEST_TMP/help.catv" "read-only"
  assert_contains "$TEST_TMP/help.catv" "modifies"
  assert_contains "$TEST_TMP/help.catv" "deletes"
}

@test "bare mdoctor prints an orientation block ending in a recommended first command" {
  local rc=0
  ./mdoctor >"$TEST_TMP/bare.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "bare mdoctor exited $rc, want 0"
  assert_contains "$TEST_TMP/bare.out" "Usage: mdoctor"
  assert_contains "$TEST_TMP/bare.out" "Commands"
  # Badged table + legend visible without a tty.
  assert_contains "$TEST_TMP/bare.out" "[SAFE]"
  assert_contains "$TEST_TMP/bare.out" "[HIGH]"
  assert_contains "$TEST_TMP/bare.out" "read-only"
  assert_contains "$TEST_TMP/bare.out" "modifies"
  assert_contains "$TEST_TMP/bare.out" "deletes"
  # The block ends in the recommended first command.
  tail -n 1 "$TEST_TMP/bare.out" | grep -q "Recommended first command: mdoctor check" \
    || fail "bare mdoctor does not end in a recommended first command"
}

@test "bare mdoctor stays a short orientation, not the full help wall" {
  ./mdoctor >"$TEST_TMP/bare2.out" 2>&1
  ./mdoctor help >"$TEST_TMP/help2.out" 2>&1
  local bare_lines help_lines
  bare_lines="$(wc -l < "$TEST_TMP/bare2.out" | tr -d ' ')"
  help_lines="$(wc -l < "$TEST_TMP/help2.out" | tr -d ' ')"
  [ "$bare_lines" -lt "$help_lines" ] \
    || fail "bare output ($bare_lines lines) is not shorter than help ($help_lines lines)"
}
