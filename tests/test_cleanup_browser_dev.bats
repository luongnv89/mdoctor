#!/usr/bin/env bats
#
# test_cleanup_browser_dev.bats
# Task 7.1 (issue #66, F-TEST-005 part 1 of 4): browser + dev cleanups.
#
# Both modules were reachable only via `clean -m` / interactive menu,
# which no test invoked. This lane asserts each runs, emits its header,
# and issues its expected target set against the Task 6.3 stub harness.
# The dev test pins the Task 0.6 opt-in: no `docker system prune`
# without MDOCTOR_ALLOW_DOCKER_PRUNE=true.
#
# Hermetic: HOME sandbox + helpers/bin stubs (docker records argv,
# never reaches a daemon). Dry-run is the default so sentinels survive
# unless a force test explicitly opts in with MDOCTOR_ASSUME_YES=true.
# Bash 3.2 compatible: no associative arrays, no mapfile, no [[ =~ ]].

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  export TMPHOME
  TMPHOME="${HOME}/.mdoctor-test-browserdev.$$.$RANDOM"
  mkdir -p "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "clean -m browser runs, emits header and the expected target set" {
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

@test "clean -m dev runs, emits header and preserves caches in dry-run" {
  mkdir -p "$TMPHOME/.cache/pip" "$TMPHOME/.npm"
  echo sentinel > "$TMPHOME/.cache/pip/f1"
  echo sentinel > "$TMPHOME/.npm/f2"
  : >"$TMPHOME/dev-dry-stub.log"
  MDOCTOR_STUB_LOG="$TMPHOME/dev-dry-stub.log" HOME="$TMPHOME" ./mdoctor clean -m dev >"$TMPHOME/dev.out" 2>&1
  assert_contains "$TMPHOME/dev.out" "Developer / power-user cleanup"
  assert_contains "$TMPHOME/dev.out" "pip"
  assert_contains "$TMPHOME/dev.out" "npm"
  assert_file_exists "$TMPHOME/.cache/pip/f1"
  assert_file_exists "$TMPHOME/.npm/f2"
}

@test "dev never issues docker system prune without the opt-in flag" {
  : >"$TMPHOME/prune-off.log"
  MDOCTOR_STUB_LOG="$TMPHOME/prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >"$TMPHOME/dev-force.out" 2>&1 || true
  assert_contains "$TMPHOME/dev-force.out" "skipping prune"
  assert_not_contains "$TMPHOME/prune-off.log" "docker system prune"
  : >"$TMPHOME/prune-on.log"
  MDOCTOR_STUB_LOG="$TMPHOME/prune-on.log" MDOCTOR_ALLOW_DOCKER_PRUNE=true MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >"$TMPHOME/dev-optin.out" 2>&1 || true
  assert_contains "$TMPHOME/prune-on.log" "docker system prune -af --volumes"
}
