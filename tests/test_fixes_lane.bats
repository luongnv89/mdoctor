#!/usr/bin/env bats
# Issue #62 (Task 6.3, part 1 of the fixes/ test lane): the stub-PATH
# harness plus exact-command-sequence coverage for the five macOS-only fix
# modules — audio, disk, spotlight, timemachine, wifi.
#
# Every privileged command resolves to the recording sudo stub (records
# argv, refuses to run) and every macOS binary to tests/helpers/bin-macos,
# so the recorded sequences prove both what each module issues and that
# nothing real ever executed. Platform branches are forced per test
# (fix_lane_as_macos / fix_lane_as_linux), keeping the lane green on the
# macOS, Linux and Bash 3.2 CI lanes alike. The dry-run honour guard and
# the remaining five targets are issue #63 scope.

load 'helpers/assert'
load 'helpers/fixes_lane'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Library environment + stub PATH load at file scope: bats runs setup_file
# in a separate process, so only exported variables survive into tests —
# function definitions do not. File-scope code re-runs in every test's
# own process, which is exactly what the lib functions need.
fix_lane_load_env
fix_lane_stub_path

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  TEST_TMP="$(mktemp -d)"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

setup() {
  export TEST_TMP
  local base="$TEST_TMP/$BATS_TEST_NUMBER"
  mkdir -p "$base"
  fix_lane_sandbox_home "$base"
  STUB_LOG="$base/stubs.log"
  export STUB_LOG
}

teardown() {
  unset MDOCTOR_STUB_LOG DRY_RUN
  unset MDOCTOR_STUB_TMUTIL_DESTOUT MDOCTOR_STUB_NETWORKSETUP_PORTS
}

@test "fixes lane: harness resolves sudo and macOS binaries to recording stubs" {
  local resolved
  resolved="$(command -v sudo)"
  [ "$resolved" = "$ROOT_DIR/tests/helpers/bin/sudo" ] || fail "sudo resolves to $resolved, not the recording stub"
  resolved="$(command -v networksetup)"
  [ "$resolved" = "$ROOT_DIR/tests/helpers/bin-macos/networksetup" ] || fail "networksetup resolves to $resolved"
  resolved="$(command -v tmutil)"
  [ "$resolved" = "$ROOT_DIR/tests/helpers/bin-macos/tmutil" ] || fail "tmutil resolves to $resolved"
}

@test "fixes lane: sandbox-home guard refuses empty, all-slash and root bases" {
  local rc=0 out
  out="$(fix_lane_sandbox_home "" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] || fail "empty base accepted (rc=$rc)"
  echo "$out" | grep -q "non-empty BASE_DIR required" || fail "wrong refusal for empty base: $out"
  rc=0
  out="$(fix_lane_sandbox_home "/" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] || fail "root base accepted (rc=$rc)"
  rc=0
  out="$(fix_lane_sandbox_home "//" 2>&1)" || rc=$?
  [ "$rc" -eq 1 ] || fail "'//' base accepted (rc=$rc)"
  # The refusal paths above must never touch the caller's HOME.
  [ "$HOME" = "$SANDBOX_HOME" ] || fail "guard path clobbered HOME"
}

@test "fixes lane: fix audio issues exactly the Core Audio restart sequence" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/audio.sh"
  local rc=0
  fix_audio >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix audio exited $rc"; }
  printf '%s\n' "sudo killall coreaudiod" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix spotlight issues exactly the index rebuild sequence" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/spotlight.sh"
  local rc=0
  fix_spotlight >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix spotlight exited $rc"; }
  printf '%s\n' \
    "sudo mdutil -a -i off" \
    "sudo mdutil -E /" \
    "sudo mdutil -a -i on" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix timemachine issues exactly the verify sequence with a destination" {
  fix_lane_as_macos
  export MDOCTOR_STUB_TMUTIL_DESTOUT="Name: TestBackup
Mount point: /Volumes/Backup"
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/timemachine.sh"
  local rc=0
  fix_timemachine >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix timemachine exited $rc"; }
  printf '%s\n' \
    "tmutil destinationinfo" \
    "tmutil latestbackup" \
    "sudo tmutil verifychecksums /" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix timemachine aborts with no destination after the read-only probe" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/timemachine.sh"
  local rc=0
  fix_timemachine >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected non-zero exit for fix timemachine without a destination"
  assert_contains "$TEST_TMP/$BATS_TEST_NUMBER/out.txt" "No Time Machine destination configured."
  printf '%s\n' "tmutil destinationinfo" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix wifi issues exactly the 3-step sequence (en0 fallback)" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/wifi.sh"
  local rc=0
  fix_wifi >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix wifi exited $rc"; }
  printf '%s\n' \
    "networksetup -listallhardwareports" \
    "sudo ipconfig set en0 DHCP" \
    "sudo dscacheutil -flushcache" \
    "sudo killall -HUP mDNSResponder" \
    "networksetup -setairportpower en0 off" \
    "networksetup -setairportpower en0 on" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix wifi targets the interface detected via networksetup" {
  fix_lane_as_macos
  export MDOCTOR_STUB_NETWORKSETUP_PORTS="Hardware Port: Ethernet
Device: en1
Ethernet Address: 00:11:22:33:44:55

Hardware Port: Wi-Fi
Device: en7
Ethernet Address: aa:bb:cc:dd:ee:ff"
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/wifi.sh"
  local rc=0
  fix_wifi >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix wifi exited $rc"; }
  assert_contains "$TEST_TMP/$BATS_TEST_NUMBER/out.txt" "Detected Wi-Fi interface: en7"
  printf '%s\n' \
    "networksetup -listallhardwareports" \
    "sudo ipconfig set en7 DHCP" \
    "sudo dscacheutil -flushcache" \
    "sudo killall -HUP mDNSResponder" \
    "networksetup -setairportpower en7 off" \
    "networksetup -setairportpower en7 on" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix disk runs the sandboxed cleanup + purge sequence in force mode" {
  fix_lane_as_macos
  printf 'junk\n' >"$SANDBOX_HOME/.Trash/canary-trash.txt"
  printf 'junk\n' >"$SANDBOX_HOME/Library/Caches/canary-cache.txt"
  # Guard the guard: HOME must be the sandbox before force mode runs, so
  # the unprivileged cleanup steps below can never see the real home.
  [ "$HOME" = "$SANDBOX_HOME" ] || fail "HOME is $HOME, not the sandbox $SANDBOX_HOME"
  [ -e "$SANDBOX_HOME/.Trash/canary-trash.txt" ] || fail "canary missing before fix disk (vacuous assertion)"
  [ -e "$SANDBOX_HOME/Library/Caches/canary-cache.txt" ] || fail "cache canary missing before fix disk"
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/disk.sh"
  local rc=0
  fix_disk >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix disk exited $rc"; }
  printf '%s\n' "sudo purge" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  [ ! -e "$SANDBOX_HOME/.Trash/canary-trash.txt" ] || fail "Trash canary survived force-mode fix disk"
  [ ! -e "$SANDBOX_HOME/Library/Caches/canary-cache.txt" ] || fail "Cache canary survived force-mode fix disk"
}

@test "fixes lane: every macOS-only module refuses off-macOS with zero stubbed execs" {
  fix_lane_as_linux
  local _m _rc _out _log
  for _m in audio disk spotlight timemachine wifi; do
    # shellcheck source=/dev/null
    source "$ROOT_DIR/fixes/${_m}.sh"
    _log="$TEST_TMP/$BATS_TEST_NUMBER/refuse-${_m}.log"
    fix_lane_begin "$_log"
    _rc=0
    _out="$(fix_${_m} 2>&1)" || _rc=$?
    [ "$_rc" -ne 0 ] || fail "Expected non-zero exit for fix $_m off-macOS"
    echo "$_out" | grep -q "macOS-only" || fail "Expected macOS-only refusal message for fix $_m"
    [ ! -s "$_log" ] || fail "macOS-only binary executed by fix $_m off-macOS: $(cat "$_log")"
  done
}
