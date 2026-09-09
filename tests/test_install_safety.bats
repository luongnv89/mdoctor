#!/usr/bin/env bats
# Task 1.1: the install directory is validated before any rm -rf, and
# uninstall prompts (skippable) and reports retained config.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-install.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  echo "keep" > "$TMPHOME/home-marker.txt"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "uninstall refuses HOME as install dir and removes nothing" {
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-home.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected uninstall to refuse HOME as install dir"
  assert_file_exists "$TMPHOME/home-marker.txt"
}

@test "uninstall refuses / as install dir" {
  local rc=0
  MDOCTOR_INSTALL_DIR="/" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-root.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected uninstall to refuse / as install dir"
}

@test "uninstall refuses a directory without mdoctor markers" {
  mkdir -p "$TMPHOME/empty-dir"
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME/empty-dir" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-empty.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected uninstall to refuse a dir without mdoctor/.git markers"
  assert_contains "$TMPHOME/ref-empty.out" "no mdoctor checkout"
}

@test "non-tty uninstall without the skip flag refuses" {
  mkdir -p "$TMPHOME/fake-install/.git"
  echo "fake" > "$TMPHOME/fake-install/mdoctor"
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME/fake-install" HOME="$TMPHOME" ./uninstall.sh < /dev/null >"$TMPHOME/ref-tty.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected uninstall to refuse on non-tty without MDOCTOR_ASSUME_YES"
  assert_file_exists "$TMPHOME/fake-install/mdoctor"
  assert_contains "$TMPHOME/ref-tty.out" "MDOCTOR_ASSUME_YES"
}

@test "skip flag removes a valid checkout and names the retained config" {
  ln -s "$TMPHOME/fake-install/mdoctor" "$TMPHOME/fake-link"
  MDOCTOR_INSTALL_DIR="$TMPHOME/fake-install" MDOCTOR_BIN_LINK="$TMPHOME/fake-link" \
    MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ok.out" 2>&1
  assert_file_not_exists "$TMPHOME/fake-install/mdoctor"
  assert_file_not_exists "$TMPHOME/fake-link"
  assert_contains "$TMPHOME/ok.out" ".config/mdoctor"
}

@test "tty prompt: n aborts uninstall and removes nothing" {
  mkdir -p "$TMPHOME/fake-install2/.git"
  echo "fake" > "$TMPHOME/fake-install2/mdoctor"
  if ! command -v script >/dev/null 2>&1; then
    skip "script(1) unavailable"
  fi
  printf 'n\n' | script -qec "MDOCTOR_INSTALL_DIR='$TMPHOME/fake-install2' MDOCTOR_BIN_LINK='$TMPHOME/no-link' HOME='$TMPHOME' ./uninstall.sh" /dev/null >"$TMPHOME/tty-no.out" 2>&1 || true
  assert_file_exists "$TMPHOME/fake-install2/mdoctor"
}

@test "install refuses a binary name with /" {
  _install_seed_fixture
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
    MDOCTOR_BINARY_NAME="a/b" HOME="$TMPHOME" ./install.sh >"$TMPHOME/badname.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected install to refuse a binary name with /"
}

@test "install refuses a bin dir outside policy" {
  _install_seed_fixture
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/nope" \
    HOME="$TMPHOME" ./install.sh >"$TMPHOME/bindir.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected install to refuse a bin dir outside policy"
  assert_contains "$TMPHOME/bindir.out" "/bin"
}

@test "override install prints the ln command and honors confirmation" {
  # Task 4.2
  _install_seed_fixture
  mkdir -p "$TMPHOME/bin"
  printf 'y\n' | MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
    MDOCTOR_BINARY_NAME="mdoctor-test" HOME="$TMPHOME" ./install.sh >"$TMPHOME/override.out" 2>&1 \
    || { tail -n 20 "$TMPHOME/override.out"; fail "override-y install failed"; }
  assert_contains "$TMPHOME/override.out" 'ln -s'
  assert_file_exists "$TMPHOME/bin/mdoctor-test"
  printf 'n\n' | MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
    MDOCTOR_BINARY_NAME="mdoctor-no" HOME="$TMPHOME" ./install.sh >"$TMPHOME/override-no.out" 2>&1 || true
  assert_file_not_exists "$TMPHOME/bin/mdoctor-no"
}

@test "a regular file at the bin path is never clobbered" {
  # Task 4.2
  _install_seed_fixture
  echo "precious" > "$TMPHOME/bin/mdoctor-clobber"
  local rc=0
  MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
    MDOCTOR_BINARY_NAME="mdoctor-clobber" MDOCTOR_ASSUME_YES=true \
    HOME="$TMPHOME" ./install.sh >"$TMPHOME/clobber.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected install to refuse a regular file at the bin path"
  assert_contains "$TMPHOME/clobber.out" "not a symlink"
  assert_file_exists "$TMPHOME/bin/mdoctor-clobber"
}

@test "reinstall over mdoctor's own symlink succeeds" {
  _install_seed_fixture
  MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
    MDOCTOR_BINARY_NAME="mdoctor-test" MDOCTOR_ASSUME_YES=true \
    HOME="$TMPHOME" ./install.sh >"$TMPHOME/reinstall.out" 2>&1 \
    || { tail -n 20 "$TMPHOME/reinstall.out"; fail "own-symlink reinstall failed"; }
  assert_file_exists "$TMPHOME/bin/mdoctor-test"
}

# Shared fixture: a seed install dir (valid markers) keeps the installer
# hermetic; the override validation above is exercised deterministically.
_install_seed_fixture() {
  export MDOCTOR_SKIP_PLATFORM_CHECK=true
  export MDOCTOR_REPO_URL="$ROOT_DIR"
  # Channel main: this fixture exercises override validation, which is
  # channel-independent (stable-channel tags are covered by
  # test_release_tags.bats).
  export MDOCTOR_CHANNEL=main
  if [ ! -d "$TMPHOME/seed" ]; then
    git clone -q "$ROOT_DIR" "$TMPHOME/seed" 2>/dev/null || true
    if [ ! -f "$TMPHOME/seed/mdoctor" ]; then
      rm -rf "$TMPHOME/seed"
      mkdir -p "$TMPHOME/seed/.git"
      cp "$ROOT_DIR/mdoctor" "$TMPHOME/seed/mdoctor"
    fi
  fi
}
