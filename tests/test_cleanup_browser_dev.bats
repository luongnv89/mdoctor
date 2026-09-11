#!/usr/bin/env bats
#
# test_cleanup_browser_dev.bats
# Task 7.1 (issue #66, F-TEST-005 part 1 of 4): browser + dev cleanups.
#
# The browser module is reachable via `clean -m` / interactive menu; this
# lane asserts it runs, emits its header, and issues its expected target
# set against the Task 6.3 stub harness. The dev module was retired into
# dev_caches (issue #89): dev-specific assertions live in
# test_dev_retired.bats; the folded-target coverage below runs through
# `clean -m dev_caches`.
#
# Hermetic: HOME sandbox + helpers/bin stubs (docker records argv,
# never reaches a daemon). Dry-run is the default so sentinels survive
# unless a force test explicitly opts in with MDOCTOR_ASSUME_YES=true.
# Bash 3.2 compatible: no associative arrays, no mapfile, no [[ =~ ]].

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-browserdev.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "clean -m browser runs, emits header and the expected target set" {
  if [ "$(uname -s)" = "Darwin" ]; then
    mkdir -p "$TMPHOME/Library/Caches/Google/Chrome" "$TMPHOME/Library/Caches/com.apple.Safari" "$TMPHOME/Library/Caches/Firefox"
    echo sentinel > "$TMPHOME/Library/Caches/Google/Chrome/f1"
    echo sentinel > "$TMPHOME/Library/Caches/com.apple.Safari/f2"
    echo sentinel > "$TMPHOME/Library/Caches/Firefox/f3"
    HOME="$TMPHOME" ./mdoctor clean -m browser >"$TMPHOME/browser.out" 2>&1
    assert_contains "$TMPHOME/browser.out" "Cleaning browser caches"
    assert_contains "$TMPHOME/browser.out" "Chrome"
    assert_contains "$TMPHOME/browser.out" "Safari"
    assert_contains "$TMPHOME/browser.out" "Firefox"
    assert_file_exists "$TMPHOME/Library/Caches/Google/Chrome/f1"
    assert_file_exists "$TMPHOME/Library/Caches/com.apple.Safari/f2"
    assert_file_exists "$TMPHOME/Library/Caches/Firefox/f3"
    return 0
  fi
  mkdir -p "$TMPHOME/.cache/google-chrome" "$TMPHOME/.cache/chromium" "$TMPHOME/.cache/mozilla/firefox"
  echo sentinel > "$TMPHOME/.cache/google-chrome/f1"
  echo sentinel > "$TMPHOME/.cache/chromium/f2"
  echo sentinel > "$TMPHOME/.cache/mozilla/firefox/f3"
  HOME="$TMPHOME" ./mdoctor clean -m browser >"$TMPHOME/browser.out" 2>&1
  assert_contains "$TMPHOME/browser.out" "Cleaning browser caches"
  assert_contains "$TMPHOME/browser.out" "google-chrome"
  assert_contains "$TMPHOME/browser.out" "chromium"
  assert_contains "$TMPHOME/browser.out" "firefox"
  assert_file_exists "$TMPHOME/.cache/google-chrome/f1"
  assert_file_exists "$TMPHOME/.cache/chromium/f2"
  assert_file_exists "$TMPHOME/.cache/mozilla/firefox/f3"
}

@test "clean -m dev_caches covers the folded dev targets and preserves caches in dry-run" {
  mkdir -p "$TMPHOME/.cache/pip" "$TMPHOME/.npm" "$TMPHOME/.cache/yarn"
  echo sentinel > "$TMPHOME/.cache/pip/f1"
  echo sentinel > "$TMPHOME/.npm/f2"
  echo sentinel > "$TMPHOME/.cache/yarn/f3"
  MDOCTOR_STUB_LOG="$TMPHOME/devcaches-dry-stub.log" HOME="$TMPHOME" ./mdoctor clean -m dev_caches >"$TMPHOME/devcaches.out" 2>&1
  assert_contains "$TMPHOME/devcaches.out" "Developer caches cleanup"
  assert_contains "$TMPHOME/devcaches.out" "pip"
  assert_contains "$TMPHOME/devcaches.out" "npm"
  assert_contains "$TMPHOME/devcaches.out" "Yarn"
  assert_file_exists "$TMPHOME/.cache/pip/f1"
  assert_file_exists "$TMPHOME/.npm/f2"
  assert_file_exists "$TMPHOME/.cache/yarn/f3"
}
