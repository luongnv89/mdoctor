#!/usr/bin/env bats
#
# test_bugfix_regressions.bats
# Issue #72 (F-TEST-014): backfill a named regression test per untested
# behavioural bug fix. Every fix commit below landed with no regression
# test; each @test references its commit SHA in a `regression for <sha>`
# comment so `grep -rc 'regression for' tests/` counts ≥ 11.
#
# Hermetic by construction: fixed fixture inputs only (stub system_profiler,
# sysctl, vm_stat, ps, realpath), sandboxed HOME under the shared fixture
# root, suite-wide stub PATH via helpers/fixes_lane. No live-host health is
# asserted anywhere in this file. Bash 3.2 compatible (plain `[ ]`
# tests, indexed arrays and while-read loops only, no Bash 4+ constructs)
# so every test runs in the bash:3.2 container job.

load 'helpers/assert'
load 'helpers/fixture'
load 'helpers/fixes_lane'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Library environment + stub PATH load at file scope (same pattern as
# test_fixes_lane.bats): setup_file runs in a separate process, so only
# exported variables survive into tests.
fix_lane_load_env
fix_lane_stub_path

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-bugfixreg.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

setup() {
  export TEST_TMP
  local base="$TEST_TMP/$BATS_TEST_NUMBER"
  mkdir -p "$base/home/.config/mdoctor"
  # Sandbox HOME + whitelist location: no test may create state in the
  # developer's real home, and whitelist loads stay inside the sandbox.
  export HOME="$base/home"
  export MDOCTOR_CLEANUP_WHITELIST_FILE="$base/home/.config/mdoctor/cleanup_whitelist"
  export LOGFILE="$base/home/mdoctor.log"
  export TEST_BASE="$base"
}

teardown() {
  unset MDOCTOR_PLATFORM
  unset MDOCTOR_BT_FIXTURE
}

@test "symlink resolution follows chains silently via realpath with perl fallback" {
  # regression for a61bfca180b2d8dbd049926eaaf6b9866c797fe1 (resolve through symlinks, not bare readlink)
  # regression for 08b2880c1236ca2c10816f0eaa77746642f1e42b (realpath first, perl fallback, home fallback)
  # regression for d985f6c2806cce25fdbc21dcf3e572e928896e62 (suppress resolution-probe stderr)
  local t="$TEST_BASE/sym"
  mkdir -p "$t/real" "$t/home" "$t/shim"
  printf '#!/usr/bin/env bash\necho probe\n' >"$t/real/target.sh"
  ln -s "$t/real/target.sh" "$t/link1.sh"
  ln -s "$t/link1.sh" "$t/link2.sh"
  local fn="$t/resolve.fn.sh"
  sed -n '/^resolve_script_dir()/,/^}/p' "$ROOT_DIR/mdoctor" >"$fn"
  [ -s "$fn" ] || fail "could not extract resolve_script_dir from mdoctor"
  local fn_def
  fn_def="$(cat "$fn")"
  local want
  want="$(cd -P "$t/real" && pwd)"
  # Live resolver over a two-link chain: lands on the real dir, silent.
  local got
  got="$(RESOLVE_FN="$fn_def" bash -c 'eval "$RESOLVE_FN"; resolve_script_dir' "$t/link2.sh" 2>"$t/stderr1.txt")"
  [ "$got" = "$want" ] || fail "chained symlink resolved to '$got', want '$want'"
  [ ! -s "$t/stderr1.txt" ] || fail "symlink resolution was noisy: $(cat "$t/stderr1.txt")"
  # Failing realpath (e.g. root-owned link): stderr stays suppressed and
  # the perl fallback still lands on the real dir.
  printf '#!/usr/bin/env bash\necho "realpath: Permission denied" >&2\nexit 1\n' >"$t/shim/realpath"
  chmod +x "$t/shim/realpath"
  local got2
  got2="$(HOME="$t/home" PATH="$t/shim:$PATH" RESOLVE_FN="$fn_def" \
    bash -c 'eval "$RESOLVE_FN"; resolve_script_dir' "$t/link2.sh" 2>"$t/stderr2.txt")"
  assert_not_contains "$t/stderr2.txt" "Permission denied"
  if command -v perl >/dev/null 2>&1; then
    [ "$got2" = "$want" ] || fail "perl fallback resolved to '$got2', want '$want'"
  else
    # No perl: last-resort branch resolves relative to the link itself.
    local want_dir
    want_dir="$(cd -P "$t" && pwd)"
    [ "$got2" = "$want_dir" ] || fail "fallback resolved to '$got2', want '$want_dir'"
  fi
}

@test "empty whitelist array expands safely under set -u" {
  # regression for e98b328beb8271958c379411707b1328b665e6ec (empty whitelist array under bash 3.2)
  local t="$TEST_BASE/wl"
  mkdir -p "$t"
  : >"$MDOCTOR_CLEANUP_WHITELIST_FILE"
  # Sanitized environment on purpose: coverage runners (kcov) export
  # tracing variables (SHELLOPTS/PS4/BASH_ENV) that a `set -u` child
  # would trip over, failing this test for instrumentation reasons
  # instead of product reasons. Only the inputs under test cross over.
  env -i PATH="/usr/bin:/bin" HOME="$HOME" ROOT_DIR="$ROOT_DIR" \
    MDOCTOR_CLEANUP_WHITELIST_FILE="$MDOCTOR_CLEANUP_WHITELIST_FILE" \
    bash -c '
      set -u
      source "$ROOT_DIR/lib/platform.sh"
      source "$ROOT_DIR/lib/safety.sh"
      reload_cleanup_whitelist
      if is_whitelisted_cleanup_path "/tmp/nowhere-issue-72-xyz"; then echo "MATCH"; else echo "NOMATCH"; fi
      printf "~/.keepme-72\n" >"$MDOCTOR_CLEANUP_WHITELIST_FILE"
      reload_cleanup_whitelist
      mkdir -p "$HOME/.keepme-72"
      if is_whitelisted_cleanup_path "$HOME/.keepme-72/file.txt"; then echo "MATCH2"; else echo "NOMATCH2"; fi
    ' >"$t/out.txt" 2>"$t/err.txt"
  assert_not_contains "$t/err.txt" "unbound variable"
  assert_contains "$t/out.txt" "NOMATCH"
  assert_contains "$t/out.txt" "MATCH2"
  # The fix idiom itself must stay in the loop for the Bash 3.2 lane
  # (fixed-string match: the brackets are regex metacharacters).
  grep -qF -- '[@]+"${' "$ROOT_DIR/lib/safety.sh" \
    || fail "expected the empty-array-safe whitelist expansion in lib/safety.sh"
}

@test "clean dispatch avoids empty-array expansion" {
  # regression for 875fc6eda8be8005e5eeafb824a550e5528df879 (empty array expansion in clean dispatch under bash 3.2)
  assert_not_contains "$ROOT_DIR/mdoctor" 'cleanup_args[@]'
  local t="$TEST_BASE/clean"
  mkdir -p "$t"
  HOME="$TEST_BASE/home" "$ROOT_DIR/mdoctor" clean -m trash >"$t/out.txt" 2>"$t/err.txt" || {
    local rc=$?
    cat "$t/out.txt" "$t/err.txt" >&2 || true
    fail "mdoctor clean -m trash exited $rc (expected 0)"
  }
  assert_not_contains "$t/err.txt" "unbound variable"
  assert_contains "$t/out.txt" "Trash"
}

@test "bluetooth device list renders every connected device in-shell" {
  # regression for 83565173852d07a9a6556969539de659a3e6a20a (orphaned spinner from pipe subshell in bluetooth check)
  assert_not_contains "$ROOT_DIR/checks/bluetooth.sh" '| while IFS= read -r dline'
  assert_contains "$ROOT_DIR/checks/bluetooth.sh" 'done <<< "$(printf'
  local t="$TEST_BASE/btloop"
  mkdir -p "$t/shim"
  cat >"$t/bt.txt" <<'EOF'
Bluetooth:

    Apple Bluetooth Software Version: 8.0.5d7

      Chipset: BCM_4350C2
      State: On
      Connected:
          MX Anywhere 3S:
            Address: 09-12-4B-5A-8B-81
            Minor Type: Mouse
          AirPods Pro:
            Address: 34-E7-11-22-33-44
            Minor Type: Headphones
      Not Connected:
          Old Keyboard:
            Address: AA-BB-CC-DD-EE-FF
            Minor Type: Keyboard
EOF
  printf '#!/usr/bin/env bash\ncat "$MDOCTOR_BT_FIXTURE"\n' >"$t/shim/system_profiler"
  chmod +x "$t/shim/system_profiler"
  MDOCTOR_BT_FIXTURE="$t/bt.txt" PATH="$t/shim:$PATH" \
    bash -c '
      source "$ROOT_DIR/lib/platform.sh"
      source "$ROOT_DIR/lib/common.sh"
      source "$ROOT_DIR/lib/logging.sh"
      source "$ROOT_DIR/lib/safety.sh"
      init_colors; MDOCTOR_DIR="$ROOT_DIR"; export MDOCTOR_DIR OPLOG_ENABLED=false
      source "$ROOT_DIR/checks/bluetooth.sh"
      check_bluetooth' >"$t/out.txt" 2>"$t/err.txt" || fail "check_bluetooth exited non-zero"
  # Every connected device line is emitted (the pipe-subshell bug lost them).
  assert_contains "$t/out.txt" "MX Anywhere 3S (Mouse)"
  assert_contains "$t/out.txt" "AirPods Pro (Headphones)"
}

@test "spinner subshell traps SIGTERM and progress_stop reaps it silently" {
  # regression for 942b92f867131b59a9c51ea9d3c06c47cc144e1f (spinner Terminated: 15 message on exit)
  assert_contains "$ROOT_DIR/lib/common.sh" "trap 'exit 0' TERM"
  local t="$TEST_BASE/spin"
  mkdir -p "$t"
  # A plain background subshell without the trap dies by signal (wait
  # reports 143); with the fix's trap it exits 0 silently. Builtin loop
  # (not `sleep`) so the trap fires immediately instead of after the
  # foreground child completes.
  bash -c '( trap "exit 0" TERM; while :; do :; done ) & _p=$!; sleep 0.2; kill -TERM "$_p"; wait "$_p"; printf "rc=%s\n" "$?"' \
    >"$t/out.txt" 2>"$t/err.txt"
  assert_contains "$t/out.txt" "rc=0"
  [ ! -s "$t/err.txt" ] || fail "trapped spinner reap was noisy: $(cat "$t/err.txt")"
}

@test "disk usage resolves through the Data-volume helper" {
  # regression for b13e365539aa6687d99d38a527c3b3685e2b79ef (accurate disk usage on macOS APFS via Data volume)
  assert_contains "$ROOT_DIR/checks/disk.sh" '$(_disk_root)'
  local t="$TEST_BASE/disk"
  mkdir -p "$t"
  bash -c '
    source "$ROOT_DIR/lib/platform.sh"
    source "$ROOT_DIR/lib/disk.sh"
    _disk_root
    kb_to_human 1048576
    kb_to_human 2048
    kb_to_human 512' >"$t/out.txt" 2>"$t/err.txt" || fail "_disk_root probe exited non-zero"
  if is_linux; then
    assert_contains "$t/out.txt" "^/$"
  else
    assert_not_contains "$t/err.txt" "unbound variable"
  fi
  assert_contains "$t/out.txt" "1.00 GB"
  assert_contains "$t/out.txt" "2.00 MB"
  assert_contains "$t/out.txt" "512 KB"
}

@test "zombie processes list per-PID details with a kill-HUP action" {
  # regression for 41083b4f7a9bd63bdf7b7a3261c949d0d84bb21e (zombie details + cleanup command in performance check)
  local t="$TEST_BASE/zombie"
  mkdir -p "$t/shim"
  cat >"$t/shim/ps" <<'EOF'
#!/usr/bin/env bash
# Fixed-input ps stub: two zombies sharing one parent, empty top lists.
if [ "$1" = "-eo" ] && [ "$2" = "stat" ]; then
  printf 'STAT\nZ\nZ\nS\n'
elif [ "$1" = "-eo" ] && [ "$2" = "pid,ppid,stat,comm" ]; then
  printf '  PID  PPID STAT COMMAND\n  111     1 Z    defunct-worker\n  222     1 Z    defunct-helper\n'
else
  printf ''
fi
EOF
  chmod +x "$t/shim/ps"
  PATH="$t/shim:$PATH" \
    bash -c '
      source "$ROOT_DIR/lib/platform.sh"
      source "$ROOT_DIR/lib/common.sh"
      source "$ROOT_DIR/lib/logging.sh"
      source "$ROOT_DIR/lib/safety.sh"
      init_colors; MDOCTOR_DIR="$ROOT_DIR"; export MDOCTOR_DIR OPLOG_ENABLED=false; ACTIONS=()
      source "$ROOT_DIR/lib/disk.sh"
      source "$ROOT_DIR/checks/performance.sh"
      check_performance
      printf "ACTIONS:[%s]\n" "${ACTIONS[*]}"' >"$t/out.txt" 2>"$t/err.txt" || fail "check_performance exited non-zero"
  assert_contains "$t/out.txt" "Zombie process details"
  assert_contains "$t/out.txt" "PID 111 → Parent 1 — defunct-worker"
  assert_contains "$t/out.txt" "PID 222 → Parent 1 — defunct-helper"
  assert_contains "$t/out.txt" "kill -HUP 1"
}

@test "total memory comes from hw.memsize, not summed vm_stat pages" {
  # regression for 0966012e7f9851a4cb7b814433812527a3fd90fc (hw.memsize for accurate total memory reporting)
  assert_contains "$ROOT_DIR/checks/system.sh" "hw.memsize"
  local t="$TEST_BASE/mem"
  mkdir -p "$t/shim"
  cat >"$t/shim/sysctl" <<'EOF'
#!/usr/bin/env bash
# Fixed inputs: 32 GiB physical RAM, 16k pages.
case "$2" in
  hw.pagesize) echo "16384" ;;
  hw.memsize) echo "34359738368" ;;
  vm.loadavg) echo "{ 1.25 0.97 0.83 }" ;;
  *) exit 1 ;;
esac
EOF
  cat >"$t/shim/vm_stat" <<'EOF'
#!/usr/bin/env bash
cat <<'STAT'
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               20000.
Pages active:                            100000.
Pages inactive:                           50000.
Pages speculative:                         5000.
Pages wired down:                         80000.
STAT
EOF
  chmod +x "$t/shim/sysctl" "$t/shim/vm_stat"
  PATH="$t/shim:$PATH" \
    bash -c '
      source "$ROOT_DIR/lib/platform.sh"
      export MDOCTOR_PLATFORM="macos"
      source "$ROOT_DIR/lib/common.sh"
      source "$ROOT_DIR/lib/logging.sh"
      source "$ROOT_DIR/lib/safety.sh"
      init_colors; MDOCTOR_DIR="$ROOT_DIR"; export MDOCTOR_DIR OPLOG_ENABLED=false
      source "$ROOT_DIR/lib/disk.sh"
      source "$ROOT_DIR/checks/system.sh"
      check_system' >"$t/out.txt" 2>"$t/err.txt" || fail "check_system exited non-zero"
  # 34359738368 bytes = 32.00 GB: the pre-fix page-sum derivation reported
  # ~3.89 GB for these same inputs, so only the hw.memsize path passes.
  assert_contains "$t/out.txt" "Memory total: 32.00 GB"
}

@test "bluetooth parses the section-based Connected format with device types" {
  # regression for 9b32103d68950ce92fe1d04f9b6cb4c6149350ab (section-based Connected parsing with device types)
  # Pin the section-header match (fixed-string: ^ and $ are regex anchors).
  grep -qF -- "^      Connected:" "$ROOT_DIR/checks/bluetooth.sh" \
    || fail "expected the section-based Connected: header match in checks/bluetooth.sh"
  local t="$TEST_BASE/btparse"
  mkdir -p "$t/shim"
  cat >"$t/bt.txt" <<'EOF'
Bluetooth:

    Apple Bluetooth Software Version: 8.0.5d7

      Chipset: BCM_4350C2
      State: On
      Connected:
          MX Anywhere 3S:
            Address: 09-12-4B-5A-8B-81
            Minor Type: Mouse
          AirPods Pro:
            Address: 34-E7-11-22-33-44
            Minor Type: Headphones
      Not Connected:
          Old Keyboard:
            Address: AA-BB-CC-DD-EE-FF
            Minor Type: Keyboard
EOF
  printf '#!/usr/bin/env bash\ncat "$MDOCTOR_BT_FIXTURE"\n' >"$t/shim/system_profiler"
  chmod +x "$t/shim/system_profiler"
  MDOCTOR_BT_FIXTURE="$t/bt.txt" PATH="$t/shim:$PATH" \
    bash -c '
      source "$ROOT_DIR/lib/platform.sh"
      source "$ROOT_DIR/lib/common.sh"
      source "$ROOT_DIR/lib/logging.sh"
      source "$ROOT_DIR/lib/safety.sh"
      init_colors; MDOCTOR_DIR="$ROOT_DIR"; export MDOCTOR_DIR OPLOG_ENABLED=false
      source "$ROOT_DIR/checks/bluetooth.sh"
      check_bluetooth' >"$t/out.txt" 2>"$t/err.txt" || fail "check_bluetooth exited non-zero"
  assert_contains "$t/out.txt" "Connected Bluetooth devices: 2"
  assert_not_contains "$t/out.txt" "Old Keyboard"
  assert_not_contains "$t/out.txt" "No Bluetooth devices connected."
}
