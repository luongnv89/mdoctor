#!/usr/bin/env bats
# Issues #87/#88 (F-DEAD-015): load average, top-CPU, memory pressure
# (#87) plus swap usage and zombie scan (#88) are sampled once in
# lib/perf_probes.sh; checks/performance.sh and
# checks/diagnose_performance.sh only capture the probe record and report
# with their own severity vocabulary. These tests pin every volatile
# input (DIAG_* overrides, which the shared probes apply for both callers,
# plus a dispatching ps stub and a failing ss stub) and assert the probe
# output lines are byte-identical to the pre-extraction fixtures captured
# on the #87 base — i.e. the refactor changed no user-visible output.
# One intentional exception, asserted separately: the retired duplicate
# load sample in the contention correlation now honors the pinned load
# like every other load consumer (see the contention test below).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Host platform gate (sourced at load time like test_dry_run_semantics):
# several fixture arms below pin platform-shaped output — memory pressure
# is a kern.memorystatus level on macOS but a MemAvailable percent on
# Linux; swap is a vm.swapusage line on macOS but used/total kb on Linux;
# and the CPU+I/O contention correlation is Linux-only by design (the
# check returns early on macOS). is_macos is the same lib/platform.sh
# predicate the code under test branches on.
source "$ROOT_DIR/lib/platform.sh"

strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b(B//g' "$1"
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-perf-probes.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/stubbin"
  # Deterministic ps: dispatches on argv like the real binary's column
  # shapes (top-CPU table, top-memory table, zombie tables); the zombie
  # tables are empty so both callers take the "no zombies" path.
  cat >"$TEST_TMP/stubbin/ps" <<'EOF'
#!/bin/sh
case "$*" in
  *"%cpu"*)
    printf 'PID %%CPU COMMAND\n101 0.0 init\n102 12.5 worker\n103 3.1 helper\n104 0.2 logger\n105 45.0 builder\n106 0.0 idler\n107 1.1 watcher\n108 0.0 sleeper\n109 2.2 runner\n110 0.4 checker\n'
    ;;
  *"rss"*)
    printf 'PID RSS COMMAND\n101 1024 init\n102 204800 worker\n103 51200 helper\n104 4096 logger\n105 307200 builder\n106 512 idler\n'
    ;;
  *"ppid"*)
    printf 'PID PPID STAT COMMAND\n'
    ;;
  *)
    printf 'STAT\nS\nS\nS\n'
    ;;
esac
EOF
  chmod +x "$TEST_TMP/stubbin/ps"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/stubbin/ss"
  chmod +x "$TEST_TMP/stubbin/ss"
  # Zombie-positive variant of the dispatcher: same top-CPU/top-memory
  # tables, but the zombie tables carry two zombies sharing parent 1.
  mkdir -p "$TEST_TMP/zstubbin"
  cat >"$TEST_TMP/zstubbin/ps" <<'EOF'
#!/bin/sh
case "$*" in
  *"%cpu"*)
    printf 'PID %%CPU COMMAND\n101 0.0 init\n102 12.5 worker\n103 3.1 helper\n104 0.2 logger\n105 45.0 builder\n106 0.0 idler\n107 1.1 watcher\n108 0.0 sleeper\n109 2.2 runner\n110 0.4 checker\n'
    ;;
  *"rss"*)
    printf 'PID RSS COMMAND\n101 1024 init\n102 204800 worker\n103 51200 helper\n104 4096 logger\n105 307200 builder\n106 512 idler\n'
    ;;
  *"ppid"*)
    printf 'PID PPID STAT COMMAND\n123 1 Z defunct-worker\n124 1 Z defunct-helper\n'
    ;;
  *)
    printf 'STAT\nZ\nZ\nS\n'
    ;;
esac
EOF
  chmod +x "$TEST_TMP/zstubbin/ps"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/zstubbin/ss"
  chmod +x "$TEST_TMP/zstubbin/ss"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "shared probes are defined once in lib and called by both modules" {
  grep -q "^perf_probe_load()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_top_cpu_raw()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_mem_pressure()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_swap()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_zombies()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "perf_probe_load" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_top_cpu_raw" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_mem_pressure" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_swap" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_zombies" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_load" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_top_cpu_raw" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_mem_pressure" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_swap" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_zombies" "$ROOT_DIR/checks/diagnose_performance.sh"
  # The probes are sink-agnostic: no code line calls the reporting sinks
  # (the contract is spelled out in the header comment, excluded here;
  # the patterns are the call names so kern.memorystatus_* does not match).
  [ "$(grep -v '^#' "$ROOT_DIR/lib/perf_probes.sh" | grep -c -e 'status_ok' -e 'status_warn' -e 'status_fail' -e 'status_info' -e 'add_action' || true)" = "0" ]
}

@test "platform sampling for all five probes exists only in lib" {
  # Neither caller carries inline platform sampling for any probe: the
  # swap-thrashing macOS pressure proxy and the contention load sample
  # were converted in #88, so diagnose keeps zero memorystatus reads.
  # (checks/system.sh still samples the 1/5/15-min load triple for its
  # own report — a different shape from the probe's threshold pair,
  # out of scope with a #88 note in checks/system.sh.)
  [ "$(grep -c 'sysctl -n vm.loadavg' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'sysctl -n vm.loadavg' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'kern.memorystatus_vm_pressure_level' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'kern.memorystatus_vm_pressure_level' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'sysctl -n vm.swapusage' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'sysctl -n vm.swapusage' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'SwapTotal' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'SwapTotal' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'SwapFree' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'SwapFree' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c -e '/proc/loadavg' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c -e '/proc/loadavg' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -arcwwxo "pid,%cpu,comm"' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -arcwwxo "pid,%cpu,comm"' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,%cpu,comm' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,%cpu,comm' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,ppid,stat,comm' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,ppid,stat,comm' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo stat' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo stat' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
}

@test "diagnose healthy probe output matches the pre-extraction fixture" {
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
    DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
    DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
    DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_healthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_healthy.raw.txt" >"$TEST_TMP/probe_healthy.txt"
  grep -E "Load average|Top 10|Memory pressure|No process exceeds" "$TEST_TMP/probe_healthy.txt" | grep -vE "^[0-9]+\\. \\[" >"$TEST_TMP/probe_healthy.excerpt.txt"
  cat >"$TEST_TMP/probe_healthy.expected.txt" <<'EOF'
  ✅ Load average (0.10) within normal range for 8 cores [1%]
  ℹ️ Top 10 CPU-consuming processes:
  ✅ No process exceeds 80% CPU usage.
EOF
  # macOS reports the pinned pressure level (DIAG_MEM_PRESSURE_LEVEL=1);
  # only the Linux arm derives and prints a MemAvailable percent.
  if is_macos; then
    echo "  ✅ Memory pressure: normal" >>"$TEST_TMP/probe_healthy.expected.txt"
  else
    echo "  ✅ Memory pressure: normal (80% available)" >>"$TEST_TMP/probe_healthy.expected.txt"
  fi
  diff "$TEST_TMP/probe_healthy.expected.txt" "$TEST_TMP/probe_healthy.excerpt.txt" \
    || fail "diagnose healthy probe output differs from the pre-extraction fixture"
}

@test "diagnose unhealthy probe output matches the pre-extraction fixture" {
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_PCT="99" \
    DIAG_MEM_AVAIL_PCT="2" DIAG_MEM_PRESSURE_LEVEL="4" \
    DIAG_DISK_PCT="99" DIAG_SWAP_PCT="90" DIAG_LINUX_IOWAIT_PCT="50" \
    DIAG_CPU_USER_PCT="30" DIAG_CPU_SYS_PCT="60" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_unhealthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_unhealthy.raw.txt" >"$TEST_TMP/probe_unhealthy.txt"
  grep -E "Load average|Top 10|Memory pressure|No process exceeds" "$TEST_TMP/probe_unhealthy.txt" | grep -vE "^[0-9]+\\. \\[" >"$TEST_TMP/probe_unhealthy.excerpt.txt"
  cat >"$TEST_TMP/probe_unhealthy.expected.txt" <<'EOF'
  ❌ Load average (99.0) is >2x core count (2) [4950% ratio]
  ℹ️ Top 10 CPU-consuming processes:
  ✅ No process exceeds 80% CPU usage.
EOF
  # macOS reports the pinned pressure level (DIAG_MEM_PRESSURE_LEVEL=4);
  # only the Linux arm derives and prints a MemAvailable percent.
  if is_macos; then
    echo "  ❌ Memory pressure: critical" >>"$TEST_TMP/probe_unhealthy.expected.txt"
  else
    echo "  ❌ Memory pressure: critical (2% available)" >>"$TEST_TMP/probe_unhealthy.expected.txt"
  fi
  diff "$TEST_TMP/probe_unhealthy.expected.txt" "$TEST_TMP/probe_unhealthy.excerpt.txt" \
    || fail "diagnose unhealthy probe output differs from the pre-extraction fixture"
}

@test "check top-CPU output matches the pre-extraction fixture" {
  PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check.raw.txt" >"$TEST_TMP/probe_check.txt"
  grep -E "Top CPU processes|PID [0-9]+: [0-9.]+%" "$TEST_TMP/probe_check.txt" >"$TEST_TMP/probe_check.excerpt.txt"
  cat >"$TEST_TMP/probe_check.expected.txt" <<'EOF'
  ℹ️ Top CPU processes:
  ℹ️   PID 101: 0.0% — init
  ℹ️   PID 102: 12.5% — worker
  ℹ️   PID 103: 3.1% — helper
  ℹ️   PID 104: 0.2% — logger
  ℹ️   PID 105: 45.0% — builder
EOF
  diff "$TEST_TMP/probe_check.expected.txt" "$TEST_TMP/probe_check.excerpt.txt" \
    || fail "check top-CPU output differs from the pre-extraction fixture"
}

@test "check honors the shared-probe overrides with unchanged reporting" {
  # The DIAG_* inputs previously only affected diagnose; routed through
  # the shared probes they now pin check_performance too, while its
  # threshold vocabulary (exceeds CPU core count / critical+elevated
  # bands) is unchanged.
  # DIAG_MEM_PRESSURE_LEVEL pins the macOS sysctl arm the same way
  # DIAG_MEM_AVAIL_PCT pins the Linux MemAvailable arm; both are set so
  # the assertion below is deterministic on either platform.
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_AVAIL_PCT="2" \
    DIAG_MEM_PRESSURE_LEVEL="4" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check_pinned.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check_pinned.raw.txt" >"$TEST_TMP/probe_check_pinned.txt"
  assert_contains "$TEST_TMP/probe_check_pinned.txt" "Load average (99.0) exceeds CPU core count (2)"
  if is_macos; then
    assert_contains "$TEST_TMP/probe_check_pinned.txt" "Memory pressure: critical"
  else
    assert_contains "$TEST_TMP/probe_check_pinned.txt" "Memory pressure: critical (2% available)"
  fi
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_AVAIL_PCT="80" \
    DIAG_MEM_PRESSURE_LEVEL="1" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check_healthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check_healthy.raw.txt" >"$TEST_TMP/probe_check_healthy.txt"
  assert_contains "$TEST_TMP/probe_check_healthy.txt" "Load average (0.10) within normal range for 8 cores."
  if is_macos; then
    assert_contains "$TEST_TMP/probe_check_healthy.txt" "Memory pressure: normal"
  else
    assert_contains "$TEST_TMP/probe_check_healthy.txt" "Memory pressure: normal (80% available)"
  fi
}

@test "diagnose swap output matches the pre-extraction fixture" {
  # Live kb values vary by host, so the parenthesized quantities are
  # normalized; the percent, the severity vocabulary and the thrashing
  # line are byte-identical to the #87-base capture.
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
    DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
    DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
    DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_swap_healthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_swap_healthy.raw.txt" >"$TEST_TMP/probe_swap_healthy.txt"
  if is_macos; then
    # macOS prints the raw `sysctl vm.swapusage` line (or "unavailable"),
    # never a "<pct>% used" line; normalize the payload like the check
    # module's Swap test does.
    grep -E "Swap: |SWAP THRASHING|Potential swap" "$TEST_TMP/probe_swap_healthy.txt" \
      | sed -E 's/Swap: .*/Swap: NORM/' >"$TEST_TMP/probe_swap_healthy.excerpt.txt"
    cat >"$TEST_TMP/probe_swap_healthy.expected.txt" <<'EOF'
  ℹ️ Swap: NORM
EOF
  else
    grep -E "Swap: [0-9]+% used|SWAP THRASHING|Potential swap" "$TEST_TMP/probe_swap_healthy.txt" \
      | sed -E 's/\([^)]*\)/(NORM)/' >"$TEST_TMP/probe_swap_healthy.excerpt.txt"
    cat >"$TEST_TMP/probe_swap_healthy.expected.txt" <<'EOF'
  ✅ Swap: 0% used (NORM)
EOF
  fi
  diff "$TEST_TMP/probe_swap_healthy.expected.txt" "$TEST_TMP/probe_swap_healthy.excerpt.txt" \
    || fail "diagnose healthy swap output differs from the pre-extraction fixture"
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_PCT="99" \
    DIAG_MEM_AVAIL_PCT="2" DIAG_MEM_PRESSURE_LEVEL="4" \
    DIAG_DISK_PCT="99" DIAG_SWAP_PCT="90" DIAG_LINUX_IOWAIT_PCT="50" \
    DIAG_CPU_USER_PCT="30" DIAG_CPU_SYS_PCT="60" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_swap_unhealthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_swap_unhealthy.raw.txt" >"$TEST_TMP/probe_swap_unhealthy.txt"
  if is_macos; then
    # macOS swap arm prints the raw sysctl line; thrashing is still
    # detected, but through the macOS proxy — pressure level 4 + swap
    # over MDOCTOR_DIAG_PRESSURE_SWAP raises iowait to
    # MDOCTOR_DIAG_IOWAIT_HIGH (30), so the pinned line reads
    # "iowait=30%", not the Linux DIAG_LINUX_IOWAIT_PCT=50.
    grep -E "Swap: |SWAP THRASHING|Potential swap" "$TEST_TMP/probe_swap_unhealthy.txt" \
      | sed -E 's/Swap: .*/Swap: NORM/' >"$TEST_TMP/probe_swap_unhealthy.excerpt.txt"
    cat >"$TEST_TMP/probe_swap_unhealthy.expected.txt" <<'EOF'
  ℹ️ Swap: NORM
  ❌ SWAP THRASHING DETECTED: swap=90% iowait=30%
EOF
  else
    grep -E "Swap: [0-9]+% used|SWAP THRASHING|Potential swap" "$TEST_TMP/probe_swap_unhealthy.txt" \
      | sed -E 's/\([^)]*\)/(NORM)/' >"$TEST_TMP/probe_swap_unhealthy.excerpt.txt"
    cat >"$TEST_TMP/probe_swap_unhealthy.expected.txt" <<'EOF'
  ❌ Swap: 90% used (NORM) — critical
  ❌ SWAP THRASHING DETECTED: swap=90% iowait=50%
EOF
  fi
  diff "$TEST_TMP/probe_swap_unhealthy.expected.txt" "$TEST_TMP/probe_swap_unhealthy.excerpt.txt" \
    || fail "diagnose unhealthy swap output differs from the pre-extraction fixture"
}

@test "check swap output matches the pre-extraction fixture" {
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_AVAIL_PCT="2" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check_swap.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check_swap.raw.txt" >"$TEST_TMP/probe_check_swap.txt"
  grep -E "Swap:" "$TEST_TMP/probe_check_swap.txt" \
    | sed -E 's/Swap: .*/Swap: NORM/' >"$TEST_TMP/probe_check_swap.excerpt.txt"
  cat >"$TEST_TMP/probe_check_swap.expected.txt" <<'EOF'
  ℹ️ Swap: NORM
EOF
  diff "$TEST_TMP/probe_check_swap.expected.txt" "$TEST_TMP/probe_check_swap.excerpt.txt" \
    || fail "check swap output differs from the pre-extraction fixture"
}

@test "zombie details match the pre-extraction fixture in both callers" {
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
    DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
    DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
    DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
    PATH="$TEST_TMP/zstubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_zombie_diag.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_zombie_diag.raw.txt" >"$TEST_TMP/probe_zombie_diag.txt"
  grep -E "Zombie processes: |→ Parent|Zombie process details" "$TEST_TMP/probe_zombie_diag.txt" >"$TEST_TMP/probe_zombie_diag.excerpt.txt"
  cat >"$TEST_TMP/probe_zombie_diag.expected.txt" <<'EOF'
  ⚠️ Zombie processes: 2
  ℹ️   PID 123 → Parent 1 — defunct-worker
  ℹ️   PID 124 → Parent 1 — defunct-helper
EOF
  diff "$TEST_TMP/probe_zombie_diag.expected.txt" "$TEST_TMP/probe_zombie_diag.excerpt.txt" \
    || fail "diagnose zombie output differs from the pre-extraction fixture"
  assert_contains "$TEST_TMP/probe_zombie_diag.txt" "Kill zombie parent processes: kill -HUP 1"
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_AVAIL_PCT="80" \
    PATH="$TEST_TMP/zstubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_zombie_check.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_zombie_check.raw.txt" >"$TEST_TMP/probe_zombie_check.txt"
  grep -E "Zombie processes: |→ Parent|Zombie process details" "$TEST_TMP/probe_zombie_check.txt" >"$TEST_TMP/probe_zombie_check.excerpt.txt"
  cat >"$TEST_TMP/probe_zombie_check.expected.txt" <<'EOF'
  ⚠️ Zombie processes: 2
  ℹ️ Zombie process details (PID → Parent PID — Command):
  ℹ️   PID 123 → Parent 1 — defunct-worker
  ℹ️   PID 124 → Parent 1 — defunct-helper
EOF
  diff "$TEST_TMP/probe_zombie_check.expected.txt" "$TEST_TMP/probe_zombie_check.excerpt.txt" \
    || fail "check zombie output differs from the pre-extraction fixture"
  assert_contains "$TEST_TMP/probe_zombie_check.txt" "kill -HUP 1"
}

@test "swap and zombie probes emit the proposed records" {
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/perf_probes.sh"
  local rec
  rec=$(perf_probe_swap) || fail "perf_probe_swap failed"
  if is_macos; then
    case "$rec" in
      "macos "*) : ;;
      *) fail "unexpected macOS swap record: $rec" ;;
    esac
  else
    echo "$rec" | grep -Eq '^linux [0-9]+ [0-9]+$' \
      || fail "unexpected Linux swap record: $rec"
  fi
  rec=$(PATH="$TEST_TMP/zstubbin:$PATH" perf_probe_zombies) \
    || fail "perf_probe_zombies failed"
  [ "$rec" = "$(printf '123 1 defunct-worker\n124 1 defunct-helper')" ] \
    || fail "unexpected zombie record: $rec"
  rec=$(PATH="$TEST_TMP/stubbin:$PATH" perf_probe_zombies) \
    || fail "perf_probe_zombies failed on the zombie-free stub"
  [ -z "$rec" ] || fail "expected no zombie lines, got: $rec"
}

@test "zombie probe returns 1 with no output when ps is missing" {
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/perf_probes.sh"
  mkdir -p "$TEST_TMP/emptybin"
  local out rc=0
  out=$(PATH="$TEST_TMP/emptybin" perf_probe_zombies 2>/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "expected rc 1 without ps, got $rc"
  [ -z "$out" ] || fail "expected no output without ps, got: $out"
}

@test "contention correlation honors pinned load via the shared probe" {
  # Intentional #88 change: the retired duplicate load sample routes
  # through perf_probe_load, so DIAG_LOADAVG/DIAG_CORES pin this check
  # like every other load consumer. Under the unhealthy fixed inputs the
  # pinned load (99.0 on 2 cores) plus iowait 50% is CPU+I/O contention;
  # before #88 the live load was sampled here and only the iowait leg
  # fired under the same inputs.
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_PCT="99" \
    DIAG_MEM_AVAIL_PCT="2" DIAG_MEM_PRESSURE_LEVEL="4" \
    DIAG_DISK_PCT="99" DIAG_SWAP_PCT="90" DIAG_LINUX_IOWAIT_PCT="50" \
    DIAG_CPU_USER_PCT="30" DIAG_CPU_SYS_PCT="60" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_contention.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_contention.raw.txt" >"$TEST_TMP/probe_contention.txt"
  if is_macos; then
    # macOS does not expose Linux-style CPU iowait, so
    # check_cpu_io_contention returns before sampling: the correlation
    # line is absent by design on this platform.
    assert_not_contains "$TEST_TMP/probe_contention.txt" "contention:"
  else
    assert_contains "$TEST_TMP/probe_contention.txt" "CPU+I/O contention: load=99.0 (2 cores), iowait=50%"
  fi
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
    DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
    DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
    DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor diagnose >"$TEST_TMP/probe_contention_healthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_contention_healthy.raw.txt" >"$TEST_TMP/probe_contention_healthy.txt"
  assert_not_contains "$TEST_TMP/probe_contention_healthy.txt" "contention:"
}
