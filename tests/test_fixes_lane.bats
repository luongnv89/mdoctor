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
# macOS, Linux and Bash 3.2 CI lanes alike.
#
# Issue #63 (Task 6.4, part 2 of 2) extends the lane to the remaining five
# targets — apt, bluetooth, dns, permissions and homebrew — and adds the
# dry-run honour guard: every fixes/ module must execute zero
# state-changing commands while DRY_RUN=true, so an eleventh module with
# no dry-run support fails the suite.

load 'helpers/assert'
load 'helpers/fixture'
load 'helpers/fixes_lane'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

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
  # Home-scoped fixture root (issue #73), not $TMPDIR: on macOS TMPDIR is
  # /var/folders/... (canonicalized to /private/var/folders/...), which
  # is_protected_deletion_path blanket-protects — so a TMPDIR sandbox
  # could never be cleaned by safe_remove there and the force-mode
  # canaries would always survive. The shared fixture root lives under
  # $HOME, outside every protected prefix, so it stays cleanable.
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-fixes-lane.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
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
  unset MDOCTOR_STUB_BREW_PREFIX
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

@test "fixes lane: fix bluetooth issues exactly the daemon HUP sequence" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/bluetooth.sh"
  local rc=0
  fix_bluetooth >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix bluetooth exited $rc"; }
  printf '%s\n' "sudo pkill -HUP bluetoothd" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix dns flushes exactly the macOS resolver sequence" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/dns.sh"
  local rc=0
  fix_dns >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix dns exited $rc"; }
  printf '%s\n' \
    "sudo dscacheutil -flushcache" \
    "sudo killall -HUP mDNSResponder" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix dns flushes exactly the systemd-resolved sequence on Linux" {
  fix_lane_as_linux
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/dns.sh"
  local rc=0
  fix_dns >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix dns exited $rc"; }
  printf '%s\n' "sudo resolvectl flush-caches" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix apt runs exactly the package-repair sequence on Linux" {
  fix_lane_as_linux
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/apt.sh"
  local rc=0
  fix_apt >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix apt exited $rc"; }
  # The sudo stub whitelists apt-get and execs it, so each sudo'd
  # apt-get call also lands in the apt-get stub's own record below it.
  printf '%s\n' \
    "sudo apt-get update" \
    "apt-get update" \
    "sudo dpkg --configure -a" \
    "sudo apt-get --fix-broken install -y" \
    "apt-get --fix-broken install -y" \
    "sudo apt-get upgrade -y" \
    "apt-get upgrade -y" \
    "sudo apt-get autoremove -y" \
    "apt-get autoremove -y" \
    "sudo apt-get clean" \
    "apt-get clean" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix permissions chowns exactly the Homebrew + /usr/local sequence" {
  fix_lane_as_macos
  export MDOCTOR_STUB_BREW_PREFIX="/opt/homebrew"
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/permissions.sh"
  local rc=0
  fix_permissions >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix permissions exited $rc"; }
  printf '%s\n' \
    "brew --prefix" \
    "sudo chown -R $(whoami) /opt/homebrew/share /opt/homebrew/lib /opt/homebrew/Cellar" \
    "sudo chown -R $(whoami) /usr/local" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: fix homebrew runs exactly the update-upgrade-cleanup-doctor sequence" {
  fix_lane_as_macos
  fix_lane_begin "$STUB_LOG"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/fixes/homebrew.sh"
  local rc=0
  fix_homebrew >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { cat "$TEST_TMP/$BATS_TEST_NUMBER/out.txt"; fail "fix homebrew exited $rc"; }
  printf '%s\n' \
    "brew update" \
    "brew upgrade" \
    "brew cleanup -s" \
    "brew autoremove" \
    "brew doctor" >"$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
  fix_lane_assert_sequence "$STUB_LOG" "$TEST_TMP/$BATS_TEST_NUMBER/expected.log"
}

@test "fixes lane: dry-run honour guard — every fixes/ module executes zero state-changing commands" {
  # Parameterised guard (issue #63): with dry-run active, the only argv a
  # module may put through the recording stub PATH is read-only probing
  # (tmutil destinationinfo/latestbackup, networksetup -listallhardwareports,
  # brew --prefix). Anything else — any sudo'd command, any mutating
  # command, any module forcing DRY_RUN=false locally — lands in the stub
  # log and fails, so an eleventh module with no dry-run support cannot
  # merge. Run_cmd_args short-circuits before exec under DRY_RUN=true
  # (Task 1.6 fail-closed), so a compliant module records nothing here.
  local _f _m _log _extra
  for _f in "$ROOT_DIR"/fixes/*.sh; do
    _m="$(basename "$_f" .sh)"
    fix_lane_as_macos
    case "$_m" in
      apt) fix_lane_as_linux ;;
    esac
    _log="$TEST_TMP/$BATS_TEST_NUMBER/guard-$_m.log"
    : >"$_log"
    export MDOCTOR_STUB_LOG="$_log"
    export DRY_RUN=true
    # shellcheck source=/dev/null
    source "$_f"
    "fix_$_m" >/dev/null 2>&1 || true
    _extra="$(grep -Ev '^(tmutil (destinationinfo|latestbackup)|networksetup -listallhardwareports|brew --prefix)$' "$_log" || true)"
    [ -z "$_extra" ] || fail "dry-run guard violated by fix $_m — executed under DRY_RUN=true: $_extra"
  done
}

@test "fixes lane: ./mdoctor fix permissions on Linux issues no chown even in force mode" {
  # Closing the loop on Task 1.2: run the real CLI (not the module function)
  # with force mode on, and assert the dispatch guard refuses before any
  # chown reaches the recording sudo stub. platform.sh re-detects the OS in
  # the fresh ./mdoctor process, so a per-test uname shim forces Linux on
  # every CI lane (macOS, Linux, Bash 3.2) identically.
  local shim_dir="$TEST_TMP/$BATS_TEST_NUMBER/shim"
  mkdir -p "$shim_dir"
  printf '#!/usr/bin/env bash\necho Linux\n' >"$shim_dir/uname"
  chmod +x "$shim_dir/uname"
  fix_lane_begin "$STUB_LOG"
  local rc=0
  DRY_RUN=false HOME="$SANDBOX_HOME" MDOCTOR_STUB_LOG="$STUB_LOG" \
    PATH="$shim_dir:$ROOT_DIR/tests/helpers/bin:$PATH" \
    "$ROOT_DIR/mdoctor" fix permissions >"$TEST_TMP/$BATS_TEST_NUMBER/out.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected ./mdoctor fix permissions to refuse on Linux"
  assert_contains "$TEST_TMP/$BATS_TEST_NUMBER/out.txt" "macOS-only"
  if grep -q chown "$STUB_LOG"; then
    fail "chown reached the stub PATH on Linux: $(cat "$STUB_LOG")"
  fi
}

@test "fixes lane: every macOS-only module refuses off-macOS with zero stubbed execs" {
  fix_lane_as_linux
  local _m _rc _out _log
  for _m in audio disk spotlight timemachine wifi bluetooth permissions; do
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
