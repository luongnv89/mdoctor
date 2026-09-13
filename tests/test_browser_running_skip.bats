#!/usr/bin/env bats
#
# test_browser_running_skip.bats
# Issue #112 (Task 12.9): two honesty fixes.
#
#  1. `downloads` is a report-only module: it is registered SAFE, carries
#     no destructive pre-flight, needs no confirmation under --force and
#     its --force run still lists — but never deletes — matching files.
#     The full engine drops it from PROGRESS_TOTAL and the destructive
#     pre-flight.
#  2. `browser` skips each of its six cache targets when pgrep finds the
#     browser running (the skip is logged and happens before the safety
#     call); when pgrep reports nothing running, --force still deletes.
#
# Hermetic: HOME sandbox + helpers/bin stubs. The pgrep stub never
# inspects real processes: exit 1 by default, exit 0 when the probe is
# listed in MDOCTOR_STUB_PGREP_RUNNING (or `all`).
# Bash 3.2 compatible: no associative arrays, no mapfile, no [[ =~ ]].

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  # Hermetic stubs (also set by tests/run.sh; repeated so this file
  # passes standalone): docker/apt-get/sudo/pgrep never touch the host.
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-browserskip.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

# _mk_browser_caches HOME — create this platform's three cache dirs with
# sentinel files (both trees, so function-level tests can flip is_macos).
_mk_browser_caches() {
  local h="$1"
  mkdir -p "$h/Library/Caches/Google/Chrome" "$h/Library/Caches/com.apple.Safari" "$h/Library/Caches/Firefox"
  mkdir -p "$h/.cache/google-chrome" "$h/.cache/chromium" "$h/.cache/mozilla/firefox"
  echo sentinel > "$h/Library/Caches/Google/Chrome/f1"
  echo sentinel > "$h/Library/Caches/com.apple.Safari/f2"
  echo sentinel > "$h/Library/Caches/Firefox/f3"
  echo sentinel > "$h/.cache/google-chrome/f4"
  echo sentinel > "$h/.cache/chromium/f5"
  echo sentinel > "$h/.cache/mozilla/firefox/f6"
}

# _platform_sentinels HOME — print this platform's sentinel paths.
_platform_sentinels() {
  if is_macos; then
    printf '%s\n' "$1/Library/Caches/Google/Chrome/f1" "$1/Library/Caches/com.apple.Safari/f2" "$1/Library/Caches/Firefox/f3"
  else
    printf '%s\n' "$1/.cache/google-chrome/f4" "$1/.cache/chromium/f5" "$1/.cache/mozilla/firefox/f6"
  fi
}

@test "browser cache targets are skipped and logged when pgrep reports the browser running" {
  _mk_browser_caches "$TMPHOME"
  MDOCTOR_STUB_PGREP_RUNNING=all MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" \
    ./mdoctor clean -m browser --force >"$TMPHOME/browser-skip.out" 2>&1
  local skips
  skips="$(grep -c 'Skipping .* cache' "$TMPHOME/browser-skip.out")"
  [ "$skips" -eq 3 ] || {
    cat "$TMPHOME/browser-skip.out" >&2
    fail "expected 3 logged skips on this platform, got $skips"
  }
  # The destructive path was never reached: sentinels survive --force.
  local f
  while IFS= read -r f; do
    assert_file_exists "$f"
  done < <(_platform_sentinels "$TMPHOME")
}

@test "browser cache targets are deleted under --force when pgrep finds nothing running" {
  _mk_browser_caches "$TMPHOME"
  MDOCTOR_STUB_PGREP_RUNNING="" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" \
    ./mdoctor clean -m browser --force >"$TMPHOME/browser-del.out" 2>&1
  assert_not_contains "$TMPHOME/browser-del.out" "Skipping"
  local f
  while IFS= read -r f; do
    assert_file_not_exists "$f"
  done < <(_platform_sentinels "$TMPHOME")
}

@test "all six browser cache call sites skip on a running browser (pgrep stub)" {
  # Function-level: source the module once, then run each platform branch
  # with all six cache dirs present — three skips per branch, six total.
  # The subshell contains the HOME/DRY_RUN/is_macos overrides.
  _mk_browser_caches "$TMPHOME"
  (
    source "$ROOT_DIR/lib/context.sh"
    mdoctor_context_init
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/logging.sh"
    source "$ROOT_DIR/lib/safety.sh"
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    export HOME="$TMPHOME"
    export LOGFILE="$TMPHOME/browser-func.log"
    export DRY_RUN=true
    export MDOCTOR_STUB_PGREP_RUNNING=all
    # shellcheck source=/dev/null
    source "$ROOT_DIR/cleanups/browser.sh"

    is_macos() { return 0; }
    clean_browser_caches >"$TMPHOME/six-macos.out" 2>&1
    is_macos() { return 1; }
    clean_browser_caches >"$TMPHOME/six-linux.out" 2>&1
  )

  local mac_skips linux_skips
  mac_skips="$(grep -c 'Skipping .* cache' "$TMPHOME/six-macos.out")"
  linux_skips="$(grep -c 'Skipping .* cache' "$TMPHOME/six-linux.out")"
  [ "$mac_skips" -eq 3 ] || fail "macOS branch: expected 3 skips, got $mac_skips"
  [ "$linux_skips" -eq 3 ] || fail "Linux branch: expected 3 skips, got $linux_skips"
  for label in Chrome Safari Firefox google-chrome chromium firefox; do
    if ! grep -q "Skipping ${label} cache" "$TMPHOME/six-macos.out" \
      && ! grep -q "Skipping ${label} cache" "$TMPHOME/six-linux.out"; then
      fail "no logged skip for ${label}"
    fi
  done
}

@test "firefox-esr process name also skips the Linux firefox cache" {
  # Debian's stock firefox-esr binary runs as "firefox-esr" — pgrep -x
  # firefox does not match it, but it shares ~/.cache/mozilla/firefox.
  _mk_browser_caches "$TMPHOME"
  (
    source "$ROOT_DIR/lib/context.sh"
    mdoctor_context_init
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/logging.sh"
    source "$ROOT_DIR/lib/safety.sh"
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    export HOME="$TMPHOME"
    export LOGFILE="$TMPHOME/browser-esr.log"
    export DRY_RUN=true
    export MDOCTOR_STUB_PGREP_RUNNING=firefox-esr
    # shellcheck source=/dev/null
    source "$ROOT_DIR/cleanups/browser.sh"

    is_macos() { return 1; }
    clean_browser_caches >"$TMPHOME/esr.out" 2>&1
  )
  grep -q "Skipping firefox cache.*firefox-esr is running" "$TMPHOME/esr.out" \
    || { cat "$TMPHOME/esr.out" >&2; fail "firefox-esr did not trigger the skip"; }
  # The other Linux targets were not skipped by the esr-only stub.
  assert_not_contains "$TMPHOME/esr.out" "Skipping google-chrome cache"
  assert_not_contains "$TMPHOME/esr.out" "Skipping chromium cache"
}

@test "downloads is report-only: --force lists matches, deletes nothing, no gate" {
  # A >500MB sparse fixture (1 real byte) aged past the 7-day threshold.
  mkdir -p "$TMPHOME/Downloads"
  dd if=/dev/zero of="$TMPHOME/Downloads/huge.bin" bs=1 count=1 seek=629145599 >/dev/null 2>&1
  touch -t 202001010000 "$TMPHOME/Downloads/huge.bin"

  # No MDOCTOR_ASSUME_YES and stdin is /dev/null: a report-only module
  # must not sit behind the destructive-confirmation gate.
  HOME="$TMPHOME" ./mdoctor clean -m downloads --force </dev/null \
    >"$TMPHOME/downloads-force.out" 2>&1
  assert_contains "$TMPHOME/downloads-force.out" "report-only"
  assert_contains "$TMPHOME/downloads-force.out" "huge.bin"
  assert_not_contains "$TMPHOME/downloads-force.out" "Pre-flight Safety Summary"
  assert_not_contains "$TMPHOME/downloads-force.out" "Proceed with deletion"
  assert_file_exists "$TMPHOME/Downloads/huge.bin"
}

@test "downloads stays out of the engine's destructive pre-flight and progress" {
  MDOCTOR_PREFLIGHT_ONLY=true MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" \
    ./cleanup.sh --force >"$TMPHOME/engine-pf.out" 2>&1 || true
  assert_not_contains "$TMPHOME/engine-pf.out" "Downloads"
  assert_not_contains "$TMPHOME/engine-pf.out" "downloads"

  # Full dry-run: the report-only module is not a progress step.
  HOME="$TMPHOME" ./cleanup.sh --dry-run >"$TMPHOME/engine-dry.out" 2>&1
  assert_not_contains "$TMPHOME/engine-dry.out" "Downloads"
  local want_total
  if is_macos; then want_total=7; else want_total=6; fi
  grep -q "➤ \[[0-9]*/${want_total}\]" "$TMPHOME/engine-dry.out" \
    || fail "expected ${want_total} progress steps in engine dry-run"
}
