#!/usr/bin/env bats
# Issue #70: installer/uninstaller round trip, ported from the CI
# release-sanity inline block into a real test file so it runs locally
# (`./tests/run.sh tests/test_installer.bats`) and on every OS lane.
# Uses the same environment overrides as the old CI block
# (MDOCTOR_REPO_URL, MDOCTOR_INSTALL_DIR, MDOCTOR_BIN_DIR,
# MDOCTOR_BINARY_NAME, MDOCTOR_ASSUME_YES) with two harness-only
# additions: MDOCTOR_CHANNEL=main (hermetic — needs no release tags;
# the stable channel is covered by test_release_tags.bats) and
# MDOCTOR_SKIP_PLATFORM_CHECK=true (the documented CI/dev-only bypass
# for non-Debian-family hosts).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-inst.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/home"
  # The harness is non-tty: opt in like CI does (Task 4.2).
  export MDOCTOR_ASSUME_YES=true
  export MDOCTOR_SKIP_PLATFORM_CHECK=true
  export MDOCTOR_CHANNEL=main
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "fresh install creates the install dir and a working symlink" {
  _install_roundtrip "fresh"
  assert_dir_exists "$TEST_TMP/fresh/install"
  [ -L "$TEST_TMP/fresh/bin/mdoctor" ] || fail "expected a symlink at fresh/bin/mdoctor"
  [ "$(readlink "$TEST_TMP/fresh/bin/mdoctor")" = "$TEST_TMP/fresh/install/mdoctor" ] \
    || fail "symlink points elsewhere: $(readlink "$TEST_TMP/fresh/bin/mdoctor")"
  "$TEST_TMP/fresh/bin/mdoctor" version >"$TEST_TMP/fresh-version.out" 2>&1 \
    || fail "installed mdoctor version failed"
  "$TEST_TMP/fresh/bin/mdoctor" help >"$TEST_TMP/fresh-help.out" 2>&1 \
    || fail "installed mdoctor help failed"
}

@test "re-install over an existing install succeeds and keeps the symlink" {
  _install_roundtrip "reinst"
  mkdir -p "$TEST_TMP/reinst/bin"
  MDOCTOR_REPO_URL="$ROOT_DIR" \
  MDOCTOR_INSTALL_DIR="$TEST_TMP/reinst/install" \
  MDOCTOR_BIN_DIR="$TEST_TMP/reinst/bin" \
  MDOCTOR_BINARY_NAME="mdoctor" \
  HOME="$TEST_TMP/home" \
    ./install.sh >"$TEST_TMP/reinst-second.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/reinst-second.out"; fail "re-install over an existing install failed"; }
  [ "$(readlink "$TEST_TMP/reinst/bin/mdoctor")" = "$TEST_TMP/reinst/install/mdoctor" ] \
    || fail "re-install changed the symlink target"
  "$TEST_TMP/reinst/bin/mdoctor" version >"$TEST_TMP/reinst-version.out" 2>&1 \
    || fail "re-installed mdoctor version failed"
}

@test "uninstall removes the install dir and the symlink" {
  _install_roundtrip "uninst"
  MDOCTOR_INSTALL_DIR="$TEST_TMP/uninst/install" \
  MDOCTOR_BIN_LINK="$TEST_TMP/uninst/bin/mdoctor" \
  HOME="$TEST_TMP/home" \
    ./uninstall.sh >"$TEST_TMP/uninst-uninstall.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/uninst-uninstall.out"; fail "uninstall.sh failed"; }
  assert_contains "$TEST_TMP/uninst-uninstall.out" "has been uninstalled"
  [ ! -e "$TEST_TMP/uninst/bin/mdoctor" ] || fail "expected the symlink to be removed"
  [ ! -e "$TEST_TMP/uninst/install" ] || fail "expected the install dir to be removed"
}

@test "uninstall of a broken symlink removes the link and the install dir" {
  mkdir -p "$TEST_TMP/broken/install/.git" "$TEST_TMP/broken/bin"
  cp "$ROOT_DIR/mdoctor" "$TEST_TMP/broken/install/mdoctor"
  ln -s "$TEST_TMP/broken/install/does-not-exist" "$TEST_TMP/broken/bin/mdoctor"
  [ -L "$TEST_TMP/broken/bin/mdoctor" ] || fail "fixture setup: expected a (broken) symlink"
  [ ! -e "$TEST_TMP/broken/bin/mdoctor" ] || fail "fixture setup: expected the symlink target to be missing"
  MDOCTOR_INSTALL_DIR="$TEST_TMP/broken/install" \
  MDOCTOR_BIN_LINK="$TEST_TMP/broken/bin/mdoctor" \
  HOME="$TEST_TMP/home" \
    ./uninstall.sh >"$TEST_TMP/broken-uninstall.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/broken-uninstall.out"; fail "uninstall of a broken symlink failed"; }
  [ ! -L "$TEST_TMP/broken/bin/mdoctor" ] || fail "expected the broken symlink to be removed"
  [ ! -e "$TEST_TMP/broken/install" ] || fail "expected the install dir to be removed"
}

# _install_roundtrip STEM — fresh install per the old CI release-sanity
# recipe (same env overrides) into $TEST_TMP/<stem>/install with its
# symlink in $TEST_TMP/<stem>/bin. Fails the calling test on error.
_install_roundtrip() {
  local stem="$1"
  local install_dir="$TEST_TMP/${stem}/install"
  local bin_dir="$TEST_TMP/${stem}/bin"
  mkdir -p "$bin_dir"
  MDOCTOR_REPO_URL="$ROOT_DIR" \
  MDOCTOR_INSTALL_DIR="$install_dir" \
  MDOCTOR_BIN_DIR="$bin_dir" \
  MDOCTOR_BINARY_NAME="mdoctor" \
  HOME="$TEST_TMP/home" \
    ./install.sh >"$TEST_TMP/${stem}-install.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/${stem}-install.out"; fail "install.sh failed (${stem})"; }
}
