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

# --- Task 4.2: installer override validation + no-clobber symlink ---
# A seed install dir (valid markers) keeps the installer hermetic. A plain
# `git clone` of the checkout can fail on shallow/detached CI checkouts
# (merge refs carry no branches), so fall back to synthesized markers —
# the override validation below is exercised deterministically either way.
git clone -q "$ROOT_DIR" "$TMPHOME/seed" 2>"$TMPHOME/seed-clone.err" || echo "DBG seed-clone rc=$?"
if [ ! -f "$TMPHOME/seed/mdoctor" ]; then
  echo "DBG seed-clone lacked a checkout; synthesizing markers"
  rm -rf "$TMPHOME/seed"
  mkdir -p "$TMPHOME/seed/.git"
  cp "$ROOT_DIR/mdoctor" "$TMPHOME/seed/mdoctor"
fi
export MDOCTOR_SKIP_PLATFORM_CHECK=true
export MDOCTOR_REPO_URL="$ROOT_DIR"

# Binary name with / is rejected.
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
  MDOCTOR_BINARY_NAME="a/b" HOME="$TMPHOME" ./install.sh >"$TMPHOME/badname.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected install to refuse a binary name with /"

# Bin dir outside the policy is rejected with a message.
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/nope" \
  HOME="$TMPHOME" ./install.sh >"$TMPHOME/bindir.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected install to refuse a bin dir outside policy"
assert_contains "$TMPHOME/bindir.out" "/bin"

# Overrides print the exact ln command and require confirmation.
mkdir -p "$TMPHOME/bin"
printf 'y\n' | MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
  MDOCTOR_BINARY_NAME="mdoctor-test" HOME="$TMPHOME" ./install.sh >"$TMPHOME/override.out" 2>&1
assert_contains "$TMPHOME/override.out" 'ln -s'
assert_file_exists "$TMPHOME/bin/mdoctor-test"
printf 'n\n' | MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
  MDOCTOR_BINARY_NAME="mdoctor-no" HOME="$TMPHOME" ./install.sh >"$TMPHOME/override-no.out" 2>&1 || true
assert_file_not_exists "$TMPHOME/bin/mdoctor-no"

# A regular file at the bin path is never clobbered.
echo "precious" > "$TMPHOME/bin/mdoctor-clobber"
set +e
MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
  MDOCTOR_BINARY_NAME="mdoctor-clobber" MDOCTOR_ASSUME_YES=true \
  HOME="$TMPHOME" ./install.sh >"$TMPHOME/clobber.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected install to refuse a regular file at the bin path"
assert_contains "$TMPHOME/clobber.out" "not a symlink"
assert_file_exists "$TMPHOME/bin/mdoctor-clobber"

# Reinstall over mdoctor's own symlink succeeds.
MDOCTOR_INSTALL_DIR="$TMPHOME/seed" MDOCTOR_BIN_DIR="$TMPHOME/bin" \
  MDOCTOR_BINARY_NAME="mdoctor-test" MDOCTOR_ASSUME_YES=true \
  HOME="$TMPHOME" ./install.sh >/dev/null 2>&1
assert_file_exists "$TMPHOME/bin/mdoctor-test"

pass "install dir validation + uninstall confirmation"
