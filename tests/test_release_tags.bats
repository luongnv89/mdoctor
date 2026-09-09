#!/usr/bin/env bats
# Task 4.1: install and self-update from signed release tags.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  if ! command -v git >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    return 0
  fi
  export TEST_TMP KEYID GPG_OK GPG_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-rel.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  # GPG homedir lives directly under the fixture root, NOT inside TEST_TMP:
  # GnuPG 2.5.21 on macOS fails with "can't connect to the gpg-agent" once
  # the homedir reaches ~84 chars (agent socket path ceiling), while the
  # run-id-qualified TEST_TMP needs its length for sweep grouping. The
  # mdoctor-test-gpg-$$ name keeps the age-based stale sweep
  # (fixture_sweep_stale matches mdoctor-test-*) and the PID keeps
  # concurrent runs apart; teardown_file removes it explicitly.
  GPG_TMP="$FIXTURE_ROOT/mdoctor-test-gpg-$$"
  rm -rf "$GPG_TMP"
  mkdir -p "$GPG_TMP"
  # --- Fixture remote: working tree (including uncommitted changes) + test
  # GPG key + signed tag. A plain `git clone` would miss uncommitted edits,
  # so the fixture is copied then committed fresh.
  mkdir -p "$TEST_TMP/remote"
  cp -r "$ROOT_DIR"/. "$TEST_TMP/remote"/
  rm -rf "$TEST_TMP/remote/.git"
  git -C "$TEST_TMP/remote" init -q 2>/dev/null
  git -C "$TEST_TMP/remote" config user.name "mdoctor test"
  git -C "$TEST_TMP/remote" config user.email "test@example.com"
  git -C "$TEST_TMP/remote" add -A 2>/dev/null
  git -C "$TEST_TMP/remote" commit -qm "fixture" 2>/dev/null
  export GNUPGHOME="$GPG_TMP"
  chmod 700 "$GNUPGHOME"
  cat >"$TEST_TMP/batch" <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: mdoctor test
Name-Email: test@example.com
Expire-Date: 0
EOF
  if ! gpg --batch --gen-key "$TEST_TMP/batch" >"$TEST_TMP/genkey.log" 2>&1; then
    echo "gpg --gen-key failed (gpg: $(gpg --version 2>/dev/null | head -n 1), homedir ${#GNUPGHOME} chars):"
    cat "$TEST_TMP/genkey.log"
    return 1
  fi
  KEYID="$(gpg --list-keys --with-colons test@example.com 2>/dev/null | awk -F: '$1=="pub"{getline; print $10}' | head -n 1)"
  GPG_OK=true
  [ -n "$KEYID" ] || GPG_OK=false
  if [ "$GPG_OK" = true ]; then
    git -C "$TEST_TMP/remote" config user.signingkey "$KEYID"
    git -C "$TEST_TMP/remote" tag -s v99.99.99 -m "test release" 2>/dev/null
    export MDOCTOR_BIN_DIR="$TEST_TMP/bin"
    mkdir -p "$MDOCTOR_BIN_DIR"
    # This host may not be Debian-family/macOS (e.g. Omarchy): the documented
    # CI/dev-only bypass applies to installer tests.
    export MDOCTOR_SKIP_PLATFORM_CHECK=true
    # The installer refuses non-tty symlink creation without an explicit
    # opt-in (Task 4.2) — the harness is non-tty, so opt in like CI does.
    export MDOCTOR_ASSUME_YES=true
  fi
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  [ -n "${GPG_TMP:-}" ] && rm -rf "$GPG_TMP"
  return 0
}

setup() {
  if [ ! -d "${TEST_TMP:-}" ] || [ "${GPG_OK:-}" != true ]; then
    skip "release-tag test requires git and gpg"
  fi
}

@test "default install checks out the latest signed release tag" {
  MDOCTOR_REPO_URL="$TEST_TMP/remote" MDOCTOR_INSTALL_DIR="$TEST_TMP/install" \
    ./install.sh >"$TEST_TMP/install.out" 2>&1
  [ "$(git -C "$TEST_TMP/install" describe --tags --exact-match 2>/dev/null)" = "v99.99.99" ] \
    || fail "Expected fresh install pinned at v99.99.99"
  assert_contains "$TEST_TMP/install.out" "Verified release tag signature"
}

@test "install.sh --help names the channel opt-in" {
  ./install.sh --help >"$TEST_TMP/install-help.out" 2>&1
  assert_contains "$TEST_TMP/install-help.out" "--channel"
}

@test "self-update moves a stale tag install to a newer signed tag" {
  MDOCTOR_REPO_URL="$TEST_TMP/remote" MDOCTOR_INSTALL_DIR="$TEST_TMP/install" \
    ./install.sh >"$TEST_TMP/install.out" 2>&1
  git -C "$TEST_TMP/remote" tag -s v99.99.100 -m "test release 2" 2>/dev/null
  HOME="$TEST_TMP" "$TEST_TMP/install/mdoctor" update >"$TEST_TMP/update.out" 2>&1
  [ "$(git -C "$TEST_TMP/install" describe --tags --exact-match 2>/dev/null)" = "v99.99.100" ] \
    || fail "Expected self-update to move to v99.99.100"
}

@test "a URL as update remote is rejected before any fetch" {
  MDOCTOR_REPO_URL="$TEST_TMP/remote" MDOCTOR_INSTALL_DIR="$TEST_TMP/install" \
    ./install.sh >"$TEST_TMP/install.out" 2>&1
  local rc=0
  HOME="$TEST_TMP" MDOCTOR_UPDATE_REMOTE="https://evil.example/r.git" \
    "$TEST_TMP/install/mdoctor" update --check >"$TEST_TMP/evil.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected URL remote to be rejected"
  assert_contains "$TEST_TMP/evil.out" "not a URL"
}

@test "unsigned enforcement fails closed without the key" {
  # Empty keyring beside (not inside) the real homedir, and short for the
  # same agent-socket reason as $GPG_TMP (derived from it: $$ differs per
  # bats process, so the test cannot recompute the setup_file PID name).
  GPG_EMPTY="${GPG_TMP}-empty"
  mkdir -p "$GPG_EMPTY"
  chmod 700 "$GPG_EMPTY"
  local rc=0
  GNUPGHOME="$GPG_EMPTY" MDOCTOR_REQUIRE_TAG_SIGNATURE=true \
    MDOCTOR_REPO_URL="$TEST_TMP/remote" MDOCTOR_INSTALL_DIR="$TEST_TMP/install2" \
    ./install.sh >"$TEST_TMP/enforce.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected REQUIRE_TAG_SIGNATURE to refuse without the key"
  [ ! -d "$TEST_TMP/install2" ] || fail "Refused install must not leave a directory"
}
