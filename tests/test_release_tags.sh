#!/usr/bin/env bash
# Task 4.1: install and self-update from signed release tags.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

if ! command -v git >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  echo "SKIP: release-tag test requires git and gpg" >&2
  exit 0
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

cd "$ROOT_DIR"

# --- Fixture remote: working tree (including uncommitted changes) + test
# GPG key + signed tag. A plain `git clone` would miss uncommitted edits,
# so the fixture is copied then committed fresh.
mkdir -p "$TMPD/remote"
cp -r "$ROOT_DIR"/. "$TMPD/remote"/
rm -rf "$TMPD/remote/.git"
git -C "$TMPD/remote" init -q 2>/dev/null
git -C "$TMPD/remote" config user.name "mdoctor test"
git -C "$TMPD/remote" config user.email "test@example.com"
git -C "$TMPD/remote" add -A 2>/dev/null
git -C "$TMPD/remote" commit -qm "fixture" 2>/dev/null
export GNUPGHOME="$TMPD/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
cat >"$TMPD/batch" <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: mdoctor test
Name-Email: test@example.com
Expire-Date: 0
EOF
gpg --batch --gen-key "$TMPD/batch" >/dev/null 2>&1
KEYID="$(gpg --list-keys --with-colons test@example.com | awk -F: '$1=="pub"{getline; print $10}' | head -n 1)"
[ -n "$KEYID" ] || { echo "SKIP: gpg key generation failed" >&2; exit 0; }
git -C "$TMPD/remote" config user.signingkey "$KEYID"
git -C "$TMPD/remote" tag -s v99.99.99 -m "test release" 2>/dev/null

export MDOCTOR_BIN_DIR="$TMPD/bin"
mkdir -p "$MDOCTOR_BIN_DIR"
# This host may not be Debian-family/macOS (e.g. Omarchy): the documented
# CI/dev-only bypass applies to installer tests.
export MDOCTOR_SKIP_PLATFORM_CHECK=true
# The installer refuses non-tty symlink creation without an explicit
# opt-in (Task 4.2) — the harness is non-tty, so opt in like CI does.
export MDOCTOR_ASSUME_YES=true

# --- Default install checks out the latest release tag, verified ---
MDOCTOR_REPO_URL="$TMPD/remote" MDOCTOR_INSTALL_DIR="$TMPD/install" \
  ./install.sh >"$TMPD/install.out" 2>&1
[ "$(git -C "$TMPD/install" describe --tags --exact-match 2>/dev/null)" = "v99.99.99" ] \
  || fail "Expected fresh install pinned at v99.99.99"
assert_contains "$TMPD/install.out" "Verified release tag signature"

# --- install.sh --help names the channel opt-in ---
./install.sh --help >"$TMPD/install-help.out" 2>&1
assert_contains "$TMPD/install-help.out" "--channel"

# --- Self-update moves a stale tag install to a newer signed tag ---
git -C "$TMPD/remote" tag -s v99.99.100 -m "test release 2" 2>/dev/null
HOME="$TMPD" "$TMPD/install/mdoctor" update >"$TMPD/update.out" 2>&1
[ "$(git -C "$TMPD/install" describe --tags --exact-match 2>/dev/null)" = "v99.99.100" ] \
  || fail "Expected self-update to move to v99.99.100"

# --- A URL as remote is rejected before any fetch ---
set +e
HOME="$TMPD" MDOCTOR_UPDATE_REMOTE="https://evil.example/r.git" \
  "$TMPD/install/mdoctor" update --check >"$TMPD/evil.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected URL remote to be rejected"
assert_contains "$TMPD/evil.out" "not a URL"

# --- Unsigned enforcement fails closed without the key ---
mkdir -p "$TMPD/gnupg-empty"
chmod 700 "$TMPD/gnupg-empty"
set +e
GNUPGHOME="$TMPD/gnupg-empty" MDOCTOR_REQUIRE_TAG_SIGNATURE=true \
  MDOCTOR_REPO_URL="$TMPD/remote" MDOCTOR_INSTALL_DIR="$TMPD/install2" \
  ./install.sh >"$TMPD/enforce.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "Expected REQUIRE_TAG_SIGNATURE to refuse without the key"
[ ! -d "$TMPD/install2" ] || fail "Refused install must not leave a directory"

pass "signed release tags for install and self-update"
