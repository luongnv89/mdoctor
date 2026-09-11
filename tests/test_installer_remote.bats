#!/usr/bin/env bats
# Issue #71 (F-CI-002): cover the curl-pipe, remote-clone and
# update-in-place installer paths.
#
# The release-sanity lane only ever installed from a local path
# (MDOCTOR_REPO_URL pointed at the working tree), while the documented
# channel is the curl-pipe one-liner against the committed installer and
# the installer defaults to cloning a remote URL. This file covers the
# three paths the old lane missed:
#   1. remote clone — MDOCTOR_REPO_URL is a git:// URL served by a
#      loopback `git daemon` (a real remote transport, not a local path).
#      Dumb HTTP (python3 -m http.server) cannot serve this side: the
#      installer clones with --depth 1 and dumb HTTP has no shallow
#      capability.
#   2. curl-pipe entry — the committed install.sh is served over loopback
#      HTTP and piped into `bash` with no argv on a non-tty stdin (the
#      documented one-liner shape), asserting a working install that does
#      not hang on the Task 4.2 confirmation gate.
#   3. update-in-place vs re-clone fallback — a second installer run over
#      an existing checkout fast-forwards ("Updating...") when the
#      upstream moved, and re-clones ("Re-cloning...") when the
#      fast-forward fails; each asserted separately.
#   4. non-tty refusal — the curl-pipe shape (no argv, stdin /dev/null)
#      without MDOCTOR_ASSUME_YES fails fast naming the non-tty skip
#      instead of hanging on the confirmation prompt.
#
# Hermetic like the other installer tests: everything lives under the
# shared fixture root, HOME is sandboxed per invocation, and
# MDOCTOR_CHANNEL=main keeps the fixture tag-free (stable is covered by
# test_release_tags.bats). Bash 3.2 compatible (indexed arrays and
# while/case only — the floor in scripts/check_bash32.sh applies).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  if ! command -v git >/dev/null 2>&1 \
    || ! command -v curl >/dev/null 2>&1 \
    || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -x "$(git --exec-path)/git-daemon" ]; then
    return 0
  fi
  export TEST_TMP GIT_URL HTTP_BASE TIMEOUT_BIN DAEMONS_OK
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-remote.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/home"
  # The harness is non-tty: opt in like CI does (Task 4.2).
  export MDOCTOR_ASSUME_YES=true
  export MDOCTOR_SKIP_PLATFORM_CHECK=true
  export MDOCTOR_CHANNEL=main
  # GNU timeout proves the no-hang assertions; where it is absent (stock
  # macOS) the run.sh per-file watchdog still bounds a hang.
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
  else
    TIMEOUT_BIN=""
  fi
  # Fixture upstream: bare clone of the working tree (committed state;
  # untracked files never matter to the installer mechanics).
  git clone -q --bare "$ROOT_DIR" "$TEST_TMP/upstream.git" || return 1
  # Pin the fixture HEAD to main: the bare clone inherits the checkout's
  # HEAD (often this very auto/ branch), but the installer update path
  # pulls `origin main`, so the default shallow clone must land on main
  # for the fast-forward assertion to hold regardless of which branch
  # the working tree sits on. The checkout itself may have no local main
  # (e.g. a shallow single-branch CI checkout), so create it at the
  # checkout HEAD commit when it is missing — pointing HEAD at a
  # nonexistent ref would serve an "empty repository".
  if ! git --git-dir="$TEST_TMP/upstream.git" show-ref --verify -q refs/heads/main; then
    _fixture_head="$(git --git-dir="$TEST_TMP/upstream.git" rev-parse HEAD)" || return 1
    git --git-dir="$TEST_TMP/upstream.git" update-ref refs/heads/main "$_fixture_head" || return 1
  fi
  git --git-dir="$TEST_TMP/upstream.git" symbolic-ref HEAD refs/heads/main || return 1
  GIT_PORT="$(_free_port)" || return 1
  HTTP_PORT="$(_free_port)" || return 1
  git daemon --export-all --reuseaddr --listen=127.0.0.1 \
    --port="$GIT_PORT" --base-path="$TEST_TMP" "$TEST_TMP" \
    >"$TEST_TMP/daemon.log" 2>&1 &
  echo "$!" >"$TEST_TMP/daemon.pid"
  python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 \
    --directory "$ROOT_DIR" >"$TEST_TMP/httpd.log" 2>&1 &
  echo "$!" >"$TEST_TMP/httpd.pid"
  GIT_URL="git://127.0.0.1:${GIT_PORT}/upstream.git"
  HTTP_BASE="http://127.0.0.1:${HTTP_PORT}"
  # Readiness gates: fail fast with the server log instead of running
  # the file against dead loopback ports.
  _wait_for_remote "git" "$GIT_URL" "$TEST_TMP/daemon.log" || return 1
  _wait_for_remote "http" "$HTTP_BASE/install.sh" "$TEST_TMP/httpd.log" || return 1
  DAEMONS_OK=true
}

teardown_file() {
  if [ -f "${TEST_TMP:-}/daemon.pid" ]; then
    kill "$(cat "$TEST_TMP/daemon.pid")" 2>/dev/null || true
  fi
  if [ -f "${TEST_TMP:-}/httpd.pid" ]; then
    kill "$(cat "$TEST_TMP/httpd.pid")" 2>/dev/null || true
  fi
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

setup() {
  if [ ! -d "${TEST_TMP:-}" ] || [ "${DAEMONS_OK:-}" != true ]; then
    skip "remote-installer test requires git (+git-daemon), curl and python3"
  fi
}

@test "remote clone over the git protocol produces a working install" {
  _remote_install "proto"
  assert_dir_exists "$TEST_TMP/proto/install/.git"
  [ -L "$TEST_TMP/proto/bin/mdoctor" ] || fail "expected a symlink at proto/bin/mdoctor"
  [ "$(readlink "$TEST_TMP/proto/bin/mdoctor")" = "$TEST_TMP/proto/install/mdoctor" ] \
    || fail "symlink points elsewhere: $(readlink "$TEST_TMP/proto/bin/mdoctor")"
  "$TEST_TMP/proto/bin/mdoctor" version >"$TEST_TMP/proto-version.out" 2>&1 \
    || fail "installed mdoctor version failed"
}

@test "curl-pipe entry with no argv on non-tty stdin installs without hanging" {
  local stem="pipe"
  local install_dir="$TEST_TMP/${stem}/install"
  local bin_dir="$TEST_TMP/${stem}/bin"
  mkdir -p "$bin_dir"
  # NOTE: a `VAR=... curl ... | bash` prefix would export the overrides
  # to curl only — the piped bash (no argv, non-tty stdin) needs them in
  # its own environment, passed via `env -i` below. The sanitized
  # environment is on purpose (same idiom as test_bugfix_regressions):
  # coverage runners (kcov) export tracing variables
  # (SHELLOPTS/PS4/BASH_ENV) that the `set -u` installer child would trip
  # over, failing this test for instrumentation reasons instead of
  # product reasons. Only the inputs under test cross over; the entry
  # shape under test (script on stdin, no argv) is unchanged.
  # "$BASH" (absolute) on purpose: the sanitized PATH cannot be relied
  # on for locating bash itself.
  export HOME="$TEST_TMP/home"
  local rc_bash=0 rc_curl=0 rc_status
  if [ -n "$TIMEOUT_BIN" ]; then
    curl -fsSL "$HTTP_BASE/install.sh" | "$TIMEOUT_BIN" 120 env -i \
      PATH="/usr/local/bin:/usr/bin:/bin" \
      HOME="$TEST_TMP/home" \
      MDOCTOR_CHANNEL=main \
      MDOCTOR_REPO_URL="$GIT_URL" \
      MDOCTOR_INSTALL_DIR="$install_dir" \
      MDOCTOR_BIN_DIR="$bin_dir" \
      MDOCTOR_BINARY_NAME="mdoctor" \
      MDOCTOR_ASSUME_YES=true \
      MDOCTOR_SKIP_PLATFORM_CHECK=true \
      "$BASH" \
      >"$TEST_TMP/${stem}-install.out" 2>&1
    # One statement: any read of PIPESTATUS must happen before the next
    # command (even a bare assignment) resets it to a single element.
    rc_status=("${PIPESTATUS[@]}")
    rc_curl="${rc_status[0]}"
    rc_bash="${rc_status[1]}"
  else
    curl -fsSL "$HTTP_BASE/install.sh" | env -i \
      PATH="/usr/local/bin:/usr/bin:/bin" \
      HOME="$TEST_TMP/home" \
      MDOCTOR_CHANNEL=main \
      MDOCTOR_REPO_URL="$GIT_URL" \
      MDOCTOR_INSTALL_DIR="$install_dir" \
      MDOCTOR_BIN_DIR="$bin_dir" \
      MDOCTOR_BINARY_NAME="mdoctor" \
      MDOCTOR_ASSUME_YES=true \
      MDOCTOR_SKIP_PLATFORM_CHECK=true \
      "$BASH" \
      >"$TEST_TMP/${stem}-install.out" 2>&1
    rc_status=("${PIPESTATUS[@]}")
    rc_curl="${rc_status[0]}"
    rc_bash="${rc_status[1]}"
  fi
  [ "$rc_curl" -eq 0 ] || { tail -n 20 "$TEST_TMP/${stem}-install.out"; fail "curl of the committed installer failed"; }
  [ "$rc_bash" -ne 124 ] || fail "curl-pipe install hung (timeout killed bash)"
  [ "$rc_bash" -eq 0 ] || { tail -n 20 "$TEST_TMP/${stem}-install.out"; fail "curl-pipe install failed"; }
  [ "$(readlink "$bin_dir/mdoctor")" = "$install_dir/mdoctor" ] \
    || fail "curl-pipe install left a wrong symlink"
  "$bin_dir/mdoctor" version >"$TEST_TMP/${stem}-version.out" 2>&1 \
    || fail "curl-pipe installed mdoctor version failed"
}

@test "update-in-place fast-forwards an existing install when upstream moves" {
  _remote_install "update"
  local install_dir="$TEST_TMP/update/install"
  local bin_dir="$TEST_TMP/update/bin"
  rm -rf "$TEST_TMP/work"
  git clone -q "$GIT_URL" "$TEST_TMP/work" \
    || fail "fixture advance: clone of the loopback upstream failed"
  # The fixture upstream is a bare clone of the working tree, so its
  # HEAD is whatever branch the checkout sits on — but the installer
  # update path pulls `origin main`, so the advance must land on main.
  git -C "$TEST_TMP/work" checkout -q main \
    || fail "fixture advance: checkout of main failed"
  git -C "$TEST_TMP/work" config user.name "mdoctor test"
  git -C "$TEST_TMP/work" config user.email "test@example.com"
  git -C "$TEST_TMP/work" commit -q --allow-empty -m "remote advance $(date +%s)" \
    || fail "fixture advance: empty commit failed"
  git -C "$TEST_TMP/work" push -q "$TEST_TMP/upstream.git" main \
    || fail "fixture advance: push to the loopback upstream failed"
  MDOCTOR_REPO_URL="$GIT_URL" \
  MDOCTOR_INSTALL_DIR="$install_dir" \
  MDOCTOR_BIN_DIR="$bin_dir" \
  MDOCTOR_BINARY_NAME="mdoctor" \
  HOME="$TEST_TMP/home" \
    ./install.sh >"$TEST_TMP/update-second.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/update-second.out"; fail "update-in-place run failed"; }
  assert_contains "$TEST_TMP/update-second.out" "Updating..."
  git -C "$install_dir" log --oneline -5 | grep -q "remote advance" \
    || fail "update-in-place did not fast-forward to the new upstream commit"
  "$bin_dir/mdoctor" version >"$TEST_TMP/update-version.out" 2>&1 \
    || fail "updated mdoctor version failed"
}

@test "re-clone fallback reinstalls when the fast-forward fails" {
  _remote_install "reclone"
  local install_dir="$TEST_TMP/reclone/install"
  local bin_dir="$TEST_TMP/reclone/bin"
  # Sabotage the checkout so `git pull --ff-only origin main` cannot
  # succeed: with no origin the pull errors and the installer must take
  # the re-clone branch (same branch any pull failure takes).
  git -C "$install_dir" remote remove origin \
    || fail "fixture sabotage: removing origin failed"
  MDOCTOR_REPO_URL="$GIT_URL" \
  MDOCTOR_INSTALL_DIR="$install_dir" \
  MDOCTOR_BIN_DIR="$bin_dir" \
  MDOCTOR_BINARY_NAME="mdoctor" \
  HOME="$TEST_TMP/home" \
    ./install.sh >"$TEST_TMP/reclone-second.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/reclone-second.out"; fail "re-clone fallback run failed"; }
  assert_contains "$TEST_TMP/reclone-second.out" "Re-cloning"
  [ -d "$install_dir/.git" ] || fail "re-clone fallback left no git checkout"
  [ "$(readlink "$bin_dir/mdoctor")" = "$install_dir/mdoctor" ] \
    || fail "re-clone fallback left a wrong symlink"
  "$bin_dir/mdoctor" version >"$TEST_TMP/reclone-version.out" 2>&1 \
    || fail "re-cloned mdoctor version failed"
}

@test "curl-pipe shape without assume-yes fails fast on non-tty instead of hanging" {
  local stem="nohang"
  local install_dir="$TEST_TMP/${stem}/install"
  local bin_dir="$TEST_TMP/${stem}/bin"
  mkdir -p "$bin_dir"
  # No argv (curl-pipe entry) and stdin /dev/null (non-tty). The bin-dir
  # override arms the Task 4.2 confirmation gate; an empty ASSUME_YES is
  # the unset path (`:-false` treats both the same). The `read` must see
  # EOF and refuse — never block.
  local rc=0
  if [ -n "$TIMEOUT_BIN" ]; then
    MDOCTOR_ASSUME_YES= \
    MDOCTOR_REPO_URL="$GIT_URL" \
    MDOCTOR_INSTALL_DIR="$install_dir" \
    MDOCTOR_BIN_DIR="$bin_dir" \
    MDOCTOR_BINARY_NAME="mdoctor" \
    HOME="$TEST_TMP/home" \
      "$TIMEOUT_BIN" 60 bash "$ROOT_DIR/install.sh" </dev/null \
        >"$TEST_TMP/${stem}.out" 2>&1 || rc=$?
  else
    MDOCTOR_ASSUME_YES= \
    MDOCTOR_REPO_URL="$GIT_URL" \
    MDOCTOR_INSTALL_DIR="$install_dir" \
    MDOCTOR_BIN_DIR="$bin_dir" \
    MDOCTOR_BINARY_NAME="mdoctor" \
    HOME="$TEST_TMP/home" \
      bash "$ROOT_DIR/install.sh" </dev/null \
        >"$TEST_TMP/${stem}.out" 2>&1 || rc=$?
  fi
  [ "$rc" -ne 124 ] || fail "installer hung on the confirmation prompt instead of refusing"
  [ "$rc" -ne 0 ] || fail "expected the non-tty run without assume-yes to refuse"
  assert_contains "$TEST_TMP/${stem}.out" "non-tty"
}

# _remote_install STEM — fresh install from the loopback git daemon into
# $TEST_TMP/<stem>/install with its symlink in $TEST_TMP/<stem>/bin.
# Fails the calling test on error.
_remote_install() {
  local stem="$1"
  local install_dir="$TEST_TMP/${stem}/install"
  local bin_dir="$TEST_TMP/${stem}/bin"
  mkdir -p "$bin_dir"
  MDOCTOR_REPO_URL="$GIT_URL" \
  MDOCTOR_INSTALL_DIR="$install_dir" \
  MDOCTOR_BIN_DIR="$bin_dir" \
  MDOCTOR_BINARY_NAME="mdoctor" \
  HOME="$TEST_TMP/home" \
    ./install.sh >"$TEST_TMP/${stem}-install.out" 2>&1 \
    || { tail -n 20 "$TEST_TMP/${stem}-install.out"; fail "install.sh failed (${stem})"; }
}

# _free_port — print an unused loopback port (best effort; the readiness
# gates below fail loudly if the port was grabbed in between).
_free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

# _wait_for_remote KIND TARGET LOG — poll a loopback server until it
# answers (git: `git ls-remote`; http: `curl -fsSL`). Fails with the
# server log tail when the server never comes up.
_wait_for_remote() {
  local kind="$1" target="$2" log="$3"
  local i=0
  while [ "$i" -lt 50 ]; do
    case "$kind" in
      git)
        if git ls-remote "$target" HEAD >/dev/null 2>&1; then
          return 0
        fi
        ;;
      http)
        if curl -fsSL "$target" -o /dev/null 2>/dev/null; then
          return 0
        fi
        ;;
    esac
    i=$((i + 1))
    sleep 0.2
  done
  echo "loopback $kind server never answered ($target):"
  tail -n 20 "$log" 2>/dev/null || true
  return 1
}
