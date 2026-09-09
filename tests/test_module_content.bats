#!/usr/bin/env bats
#
# test_module_content.bats
# Task 7.4 (issue #69, F-TEST-005 part 4 of 4): behavioural assertions for
# the 33 exit-status-only modules.
#
# Of the 39 modules that execute in the suite, only 6 had any behavioural
# assertion — the rest ran as a side effect of an exit-status check, so a
# module could produce nothing and stay green. This lane attaches at least
# one content assertion (header / status / refusal string) per registered
# module, enumerated from the live `register_module` registry in `mdoctor`
# (never a hardcoded list), so a new module without a mapping fails.
#
# Hermetic: HOME sandbox + sparse PATH farm (same pattern as
# test_check_modules.bats). Cleanup runs stay in dry-run (the default),
# fix runs force DRY_RUN=true so no stub ever executes for real. No
# sudo/apt-get/docker real calls (tests/run.sh shadows them; this file
# also passes standalone by prepending helpers/bin).
#
# Bash 3.2 compatible: no associative arrays, no mapfile, no [[ =~ ]].

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

_CMD_TIMEOUT=280

_run_lim() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

_hermetic_path() {
  echo "$ROOT_DIR/tests/helpers/bin:$TEST_TMP/farm"
}

# _all_registered: every TYPE:NAME pair from the registry source.
# Parses `mdoctor` (the single registration site) so macOS-only and
# Linux-only modules are included on every lane.
_all_registered() {
  grep -E '^[[:space:]]*register_module[[:space:]]+' "$ROOT_DIR/mdoctor" \
    | awk '{print $2":"$3}'
}

# _expected_content TYPE:NAME -> fixed-string needle for the registered
# path. Empty output means "no mapping" and the guard fails naming the
# module. Patterns are step/header strings that are stable hermetically:
# for `startup` the header is used here; the systemd-fallback branch is
# pinned by the dedicated test below (the silent-module guard example).
_expected_content() {
  case "$1" in
    check:hardware) echo "Hardware Overview" ;;
    check:system) echo "System & OS" ;;
    check:disk) echo "Disk health" ;;
    check:updates) echo "pdate" ;;
    check:security) echo "Security & Privacy" ;;
    check:startup) echo "Startup Items" ;;
    check:network) echo "Network Diagnostics" ;;
    check:performance) echo "Performance & Memory" ;;
    check:storage) echo "Storage Hogs Analysis" ;;
    check:node) echo "Node.js & npm" ;;
    check:python) echo "Python & pip" ;;
    check:devtools) echo "Developer Tools" ;;
    check:shell) echo "Shell configuration files" ;;
    check:apps) echo "Application Health" ;;
    check:git_config) echo "Git & SSH Configuration" ;;
    check:containers) echo "Docker & Containers" ;;
    check:apt) echo "APT Package Manager" ;;
    check:battery) echo "Battery Health" ;;
    check:bluetooth) echo "Bluetooth Status" ;;
    check:usb) echo "USB Devices" ;;
    check:homebrew) echo "Homebrew" ;;
    diagnose:diagnose) echo "Performance Diagnosis" ;;
    cleanup:trash) echo "Emptying Trash" ;;
    cleanup:caches) echo "Cleaning user caches" ;;
    cleanup:logs) echo "Cleaning user logs" ;;
    cleanup:downloads) echo "Downloads" ;;
    cleanup:crash_reports) echo "Cleaning crash reports" ;;
    cleanup:browser) echo "Cleaning browser caches" ;;
    cleanup:dev) echo "Developer / power-user cleanup" ;;
    cleanup:dev_caches) echo "Developer caches cleanup" ;;
    cleanup:apt) echo "APT cache cleanup" ;;
    cleanup:ios_backups) echo "iOS device backups cleanup" ;;
    cleanup:xcode) echo "Xcode cleanup" ;;
    fix:dns) echo "Flushing DNS Cache" ;;
    fix:apt) echo "APT Package Manager Fix" ;;
    fix:disk) echo "Freeing Disk Space" ;;
    fix:homebrew) echo "Fixing Homebrew" ;;
    fix:permissions) echo "Resetting Permissions" ;;
    fix:spotlight) echo "Rebuilding Spotlight Index" ;;
    fix:bluetooth) echo "Resetting Bluetooth" ;;
    fix:audio) echo "Fixing Audio" ;;
    fix:wifi) echo "Fixing Wi-Fi" ;;
    fix:timemachine) echo "Time Machine Repair" ;;
    *) echo "" ;;
  esac
}

# _run_module TYPE NAME OUTFILE: hermetic single-module run.
# Exit status is intentionally ignored here (content, not exit status,
# is under test); callers assert on OUTFILE content.
_run_module() {
  local mtype="$1"
  local mname="$2"
  local outfile="$3"
  case "$mtype" in
    check)
      PATH="$(_hermetic_path)" HOME="$TEST_TMP/home" \
        _run_lim ./mdoctor check -m "$mname" >"$outfile" 2>&1 || true
      ;;
    cleanup)
      PATH="$(_hermetic_path)" HOME="$TEST_TMP/home" \
        _run_lim ./mdoctor clean -m "$mname" >"$outfile" 2>&1 || true
      ;;
    diagnose)
      PATH="$(_hermetic_path)" HOME="$TEST_TMP/home" \
        _run_lim ./mdoctor diagnose >"$outfile" 2>&1 || true
      ;;
    fix)
      PATH="$(_hermetic_path)" HOME="$TEST_TMP/home" DRY_RUN=true \
        _run_lim ./mdoctor fix "$mname" >"$outfile" 2>&1 || true
      ;;
    *)
      echo "unknown module type: $mtype" >"$outfile"
      ;;
  esac
}

# _assert_module_content TYPE NAME OUTFILE: pass when OUTFILE carries the
# module's behavioural signal. Three accept paths (in order):
#   1. the registered header/needle (normal path on the owning platform),
#   2. "Unknown <type> module" + module name (module not registered on
#      this platform — still a content assertion naming the module),
#   3. "macOS-only" (platform refusal from fix dispatch / fix modules).
# Anything else fails naming TYPE:NAME with a tail for diagnosis.
_assert_module_content() {
  local mtype="$1"
  local mname="$2"
  local outfile="$3"
  local needle=""
  needle="$(_expected_content "$mtype:$mname")"
  if [ -z "$needle" ]; then
    fail "module '$mtype:$mname' has no content assertion mapping"
  fi
  if grep -q -- "$needle" "$outfile"; then
    return 0
  fi
  if grep -q "Unknown" "$outfile" && grep -q -- "$mname" "$outfile"; then
    return 0
  fi
  if grep -q "macOS-only" "$outfile"; then
    return 0
  fi
  tail -n 15 "$outfile" >&2 || true
  fail "module '$mtype:$mname' emitted no content assertion (missing '$needle', no Unknown/macOS-only refusal)"
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-modcontent.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/farm" "$TEST_TMP/home/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TEST_TMP/home/.config/mdoctor/cleanup_whitelist"
  local _d _f _b _p _need
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        ping|nslookup|ss|ps|softwareupdate) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

@test "module content: parameterised guard fails naming any registered module without a mapping" {
  local pair mtype mname needle missing=""
  for pair in $(_all_registered); do
    mtype="${pair%%:*}"
    mname="${pair#*:}"
    needle="$(_expected_content "$pair")"
    if [ -z "$needle" ]; then
      missing="$missing $pair"
    fi
  done
  [ -z "$missing" ] || fail "registered module(s) without content assertion:$missing"
}

@test "module content: every registered module emits its content assertion" {
  local pair mtype mname out
  for pair in $(_all_registered); do
    mtype="${pair%%:*}"
    mname="${pair#*:}"
    out="$TEST_TMP/content_${mtype}_${mname}.txt"
    _run_module "$mtype" "$mname" "$out"
    [ -s "$out" ] || fail "module '$pair' produced no output at all"
    _assert_module_content "$mtype" "$mname" "$out"
  done
}

@test "module content: startup emits the systemd signal on both branches (silent-module guard example)" {
  local out="$TEST_TMP/startup_systemd.txt"
  PATH="$(_hermetic_path)" HOME="$TEST_TMP/home" \
    _run_lim ./mdoctor check -m startup >"$out" 2>&1 || true
  assert_contains "$out" "Startup Items"
  if [ "$(uname -s)" = "Darwin" ]; then
    assert_contains "$out" "Launch"
    return 0
  fi
  assert_contains "$out" "systemd"
  local nosys="$TEST_TMP/startup_nosystemd_farm"
  mkdir -p "$nosys"
  local _b
  for _b in "$TEST_TMP/farm"/*; do
    case "$(basename "$_b")" in
      systemctl) continue ;;
      *) ln -s "$_b" "$nosys/$(basename "$_b")" ;;
    esac
  done
  local out2="$TEST_TMP/startup_fallback.txt"
  PATH="$ROOT_DIR/tests/helpers/bin:$nosys" HOME="$TEST_TMP/home" \
    _run_lim ./mdoctor check -m startup >"$out2" 2>&1 || true
  assert_contains "$out2" "systemd not available; startup check skipped."
}

@test "module content: assertion names a module that produces no output" {
  : >"$TEST_TMP/silent.out"
  local out
  out="$(_assert_module_content cleanup trash "$TEST_TMP/silent.out" 2>&1)" || true
  case "$out" in
    *trash*) pass "$out" ;;
    *) fail "expected assertion failure naming 'trash', got: ${out:-<nothing>}" ;;
  esac
}
