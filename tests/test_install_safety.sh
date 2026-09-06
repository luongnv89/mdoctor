#!/usr/bin/env bash
# Task 1.1: the install directory is validated before any rm -rf, and
# uninstall prompts (skippable) and reports retained config.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-install.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

cd "$ROOT_DIR"

echo "keep" > "$TMPHOME/home-marker.txt"

# Refuses $HOME and removes nothing.
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-home.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected uninstall to refuse HOME as install dir"
assert_file_exists "$TMPHOME/home-marker.txt"

# Refuses /.
set +e
MDOCTOR_INSTALL_DIR="/" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-root.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected uninstall to refuse / as install dir"

# Refuses a directory without mdoctor markers.
mkdir -p "$TMPHOME/empty-dir"
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME/empty-dir" HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ref-empty.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected uninstall to refuse a dir without mdoctor/.git markers"
assert_contains "$TMPHOME/ref-empty.out" "no mdoctor checkout"

# Non-tty without the skip flag refuses.
mkdir -p "$TMPHOME/fake-install/.git"
echo "fake" > "$TMPHOME/fake-install/mdoctor"
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME/fake-install" HOME="$TMPHOME" ./uninstall.sh < /dev/null >"$TMPHOME/ref-tty.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected uninstall to refuse on non-tty without MDOCTOR_ASSUME_YES"
assert_file_exists "$TMPHOME/fake-install/mdoctor"
assert_contains "$TMPHOME/ref-tty.out" "MDOCTOR_ASSUME_YES"

# Skip flag removes a valid checkout and names the retained config.
ln -s "$TMPHOME/fake-install/mdoctor" "$TMPHOME/fake-link"
MDOCTOR_INSTALL_DIR="$TMPHOME/fake-install" MDOCTOR_BIN_LINK="$TMPHOME/fake-link" \
  MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./uninstall.sh >"$TMPHOME/ok.out" 2>&1
assert_file_not_exists "$TMPHOME/fake-install/mdoctor"
assert_file_not_exists "$TMPHOME/fake-link"
assert_contains "$TMPHOME/ok.out" ".config/mdoctor"

# Tty prompt: "n" aborts and removes nothing.
mkdir -p "$TMPHOME/fake-install2/.git"
echo "fake" > "$TMPHOME/fake-install2/mdoctor"
if command -v script >/dev/null 2>&1; then
  printf 'n\n' | script -qec "MDOCTOR_INSTALL_DIR='$TMPHOME/fake-install2' MDOCTOR_BIN_LINK='$TMPHOME/no-link' HOME='$TMPHOME' ./uninstall.sh" /dev/null >"$TMPHOME/tty-no.out" 2>&1 || true
  assert_file_exists "$TMPHOME/fake-install2/mdoctor"
fi

pass "install dir validation + uninstall confirmation"
