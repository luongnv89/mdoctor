#!/usr/bin/env bats
#
# Regression test for issue #104 (Task 12.1):
#   every module list the CLI prints — `check --help`, `clean --help` and
#   both unknown-module error messages — is rendered from the
#   platform-filtered registry, so each printed set equals
#   `registry_names` on the running platform and never names the other
#   platform's modules. The `clean --help` module list and the
#   `clean -i` picker menu must contain the same set.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

# registry_set TYPE — sorted registry-derived module names for TYPE on the
# running platform (subshell so registration never leaks into the test).
registry_set() {
  (
    source "$ROOT_DIR/lib/metadata.sh"
    source "$ROOT_DIR/lib/registry.sh"
    register_all_modules
    registry_names "$1"
  ) | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort
}

# help_group_set FILE — module names from "  Category:  a [RISK], b" or
# "  Category:  a, b" lines (the registry_help_group /
# registry_check_names_plain render used by usage_* help).
help_group_set() {
  sed -n 's/^  [A-Za-z]*:[[:space:]]*//p' "$1" \
    | tr ',' '\n' \
    | sed 's/^ *//; s/ .*//; /^$/d' \
    | LC_ALL=C sort
}

# listed_rows_set FILE — module names from "    name  [RISK] desc" rows
# (the list_modules_by_category render used by the check error path).
listed_rows_set() {
  sed -n 's/^    \([a-z_][a-z0-9_]*\)[[:space:]].*/\1/p' "$1" | LC_ALL=C sort
}

# available_line_set FILE — names from a single "Available modules: a, b"
# line (the registry_available_text render used by the clean error path).
available_line_set() {
  sed -n 's/^Available modules: //p' "$1" \
    | tr ',' '\n' \
    | sed 's/^ *//; /^$/d' \
    | LC_ALL=C sort
}

# menu_set FILE — names from "  [N] name   desc" picker rows (the
# select_interactive_modules render used by `clean -i`; same pattern as
# test_interactive_cleanup.bats' trash_menu_index).
menu_set() {
  sed -n 's/^ *\[[0-9][0-9]*\] *\([a-z_][a-z0-9_]*\).*/\1/p' "$1" | LC_ALL=C sort
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-listparity.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "clean --help module list and clean -i menu contain the same set" {
  HOME="$TMPHOME" ./mdoctor clean --help >"$TMPHOME/clean_help.txt" 2>&1
  HOME="$TMPHOME" ./mdoctor clean -i </dev/null >"$TMPHOME/clean_menu.txt" 2>&1
  local help_set picker_set
  help_set="$(help_group_set "$TMPHOME/clean_help.txt")"
  picker_set="$(menu_set "$TMPHOME/clean_menu.txt")"
  [ -n "$help_set" ] || fail "clean --help listed no modules"
  [ -n "$picker_set" ] || fail "clean -i menu listed no modules"
  [ "$help_set" = "$picker_set" ] || {
    printf 'clean --help set:\n%s\nclean -i menu set:\n%s\n' "$help_set" "$picker_set" >&2
    return 1
  }
}

@test "all four lists equal the platform-filtered registry" {
  HOME="$TMPHOME" ./mdoctor check --help >"$TMPHOME/check_help.txt" 2>&1
  HOME="$TMPHOME" ./mdoctor clean --help >"$TMPHOME/clean_help.txt" 2>&1
  HOME="$TMPHOME" ./mdoctor check -m bogus_nope_xyz >"$TMPHOME/check_err.txt" 2>&1 || true
  HOME="$TMPHOME" ./mdoctor clean -m bogus_nope_xyz >"$TMPHOME/clean_err.txt" 2>&1 || true

  local reg_check reg_clean
  reg_check="$(registry_set check)"
  reg_clean="$(registry_set cleanup)"
  [ -n "$reg_check" ] || fail "registry returned no check modules"
  [ -n "$reg_clean" ] || fail "registry returned no cleanup modules"

  local got
  got="$(help_group_set "$TMPHOME/check_help.txt")"
  [ "$got" = "$reg_check" ] || fail "check --help list diverged from registry"
  got="$(help_group_set "$TMPHOME/clean_help.txt")"
  [ "$got" = "$reg_clean" ] || fail "clean --help list diverged from registry"
  got="$(listed_rows_set "$TMPHOME/check_err.txt")"
  [ "$got" = "$reg_check" ] || fail "unknown-check-module error list diverged from registry"
  got="$(available_line_set "$TMPHOME/clean_err.txt")"
  [ "$got" = "$reg_clean" ] || fail "unknown-cleanup-module error list diverged from registry"
}

@test "no foreign-platform module names in help or error output" {
  {
    HOME="$TMPHOME" ./mdoctor help
    HOME="$TMPHOME" ./mdoctor check --help
    HOME="$TMPHOME" ./mdoctor clean --help
    HOME="$TMPHOME" ./mdoctor check -m bogus_nope_xyz
    HOME="$TMPHOME" ./mdoctor clean -m bogus_nope_xyz
  } >"$TMPHOME/all_lists.txt" 2>&1 || true

  if is_macos; then
    for m in battery ios_backups xcode; do
      grep -qw "$m" "$TMPHOME/all_lists.txt" || fail "expected macOS module '$m' in help/error output"
    done
    ! grep -qw apt "$TMPHOME/all_lists.txt" || fail "Linux-only module 'apt' in help/error output"
  else
    for m in battery bluetooth usb homebrew ios_backups xcode; do
      ! grep -qw "$m" "$TMPHOME/all_lists.txt" || fail "macOS-only module '$m' in help/error output"
    done
    grep -qw apt "$TMPHOME/all_lists.txt" || fail "expected Linux module 'apt' in help/error output"
  fi
}
