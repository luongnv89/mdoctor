#!/usr/bin/env bats
# Issue #87 (part 1 of 2, F-DEAD-015): load average, top-CPU and memory
# pressure are sampled once in lib/perf_probes.sh; checks/performance.sh
# and checks/diagnose_performance.sh only capture the probe record and
# report with their own severity vocabulary. These tests pin every volatile
# input (DIAG_* overrides, which the shared probes apply for both callers,
# plus a dispatching ps stub and a failing ss stub) and assert the probe
# output lines are byte-identical to the pre-extraction fixtures captured
# on main — i.e. the refactor changed no user-visible output.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

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
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "shared probes are defined once in lib and called by both modules" {
  grep -q "^perf_probe_load()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_top_cpu_raw()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "^perf_probe_mem_pressure()" "$ROOT_DIR/lib/perf_probes.sh"
  grep -q "perf_probe_load" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_top_cpu_raw" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_mem_pressure" "$ROOT_DIR/checks/performance.sh"
  grep -q "perf_probe_load" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_top_cpu_raw" "$ROOT_DIR/checks/diagnose_performance.sh"
  grep -q "perf_probe_mem_pressure" "$ROOT_DIR/checks/diagnose_performance.sh"
}

@test "platform sampling for the three probes exists only in lib" {
  # check_performance carries no inline platform sampling for the three
  # probes at all; diagnose keeps exactly one memorystatus read outside
  # them (the swap-thrashing macOS proxy, part-2 scope in #88) and no
  # inline load/top-CPU sampling. (checks/system.sh still samples load
  # for its own report — a different module, out of scope.)
  [ "$(grep -c 'sysctl -n vm.loadavg' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'sysctl -n vm.loadavg' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'kern.memorystatus_vm_pressure_level' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'kern.memorystatus_vm_pressure_level' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "1" ]
  [ "$(grep -c 'ps -arcwwxo "pid,%cpu,comm"' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -arcwwxo "pid,%cpu,comm"' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,%cpu,comm' "$ROOT_DIR/checks/performance.sh" || true)" = "0" ]
  [ "$(grep -c 'ps -eo pid,%cpu,comm' "$ROOT_DIR/checks/diagnose_performance.sh" || true)" = "0" ]
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
  ✅ Memory pressure: normal (80% available)
EOF
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
  ❌ Memory pressure: critical (2% available)
EOF
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
  env DIAG_LOADAVG="99.0" DIAG_CORES="2" DIAG_MEM_AVAIL_PCT="2" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check_pinned.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check_pinned.raw.txt" >"$TEST_TMP/probe_check_pinned.txt"
  assert_contains "$TEST_TMP/probe_check_pinned.txt" "Load average (99.0) exceeds CPU core count (2)"
  assert_contains "$TEST_TMP/probe_check_pinned.txt" "Memory pressure: critical (2% available)"
  env DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_AVAIL_PCT="80" \
    PATH="$TEST_TMP/stubbin:$PATH" \
    ./mdoctor check -m performance >"$TEST_TMP/probe_check_healthy.raw.txt" 2>&1
  strip_ansi "$TEST_TMP/probe_check_healthy.raw.txt" >"$TEST_TMP/probe_check_healthy.txt"
  assert_contains "$TEST_TMP/probe_check_healthy.txt" "Load average (0.10) within normal range for 8 cores."
  assert_contains "$TEST_TMP/probe_check_healthy.txt" "Memory pressure: normal (80% available)"
}
