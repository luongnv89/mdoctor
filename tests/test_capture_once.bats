#!/usr/bin/env bats
#
# test_capture_once.bats
# Issue #100 (F-PERF-011/013/017): each slow report is captured at most
# once per `mdoctor` run. checks/battery.sh used to fork
# `system_profiler SPPowerDataType` 3x, `ioreg` 2x and `pmset -g batt`
# 3x; `dpkg -l` ran 3x across checks/apt.sh + checks/apps.sh +
# checks/security.sh; and the perf consumers re-read /proc/meminfo,
# /proc/loadavg, nproc and vm_stat per field. Now one capture per report
# lives in lib/perf_probes.sh (perf_capture_* samplers, _PERF_* globals,
# *_DONE flags) and every consumer parses the shared snapshot in-shell.
#
# Acceptance coverage ("stub-PATH invocation counter"):
#   * argv-logging stub binaries shadow the real tools on PATH; a count
#     of matching log lines proves each report is fetched <= 1x per run.
#   * The real system_profiler/ioreg/pmset/dpkg/vm_stat/nproc are never
#     invoked: the stubs intercept by name on every host.
#   * battery and the Debian dpkg consumers are exercised in a `bash -c`
#     process with the exported MDOCTOR_PLATFORM predicate pinned (the
#     same forcing tests/helpers/fixes_lane uses), so the counts hold on
#     any host — the registry gates `check -m battery` to macOS anyway.
#   * `dpkg -l` is counted by its exact argv line; `dpkg --audit` and
#     the other system_profiler data types (SPHardwareDataType,
#     SPBluetoothDataType, SPUSBDataType — one capture each already) are
#     different reports and stay out of scope.
#
# Bash 3.2 compatible; stubs are POSIX sh. No live-host health asserted.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# Host platform predicates for platform-conditional expectations.
source "$ROOT_DIR/lib/platform.sh"

strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b(B//g' "$1"
}

# _count_log LOGFILE PATTERN — fixed-string count; prints 0 on an
# absent/empty log so assertions never trip on grep's exit code.
_count_log() {
  local log="$1" pat="$2"
  if [ -f "$log" ]; then
    grep -cF -- "$pat" "$log" || true
  else
    echo 0
  fi
}

# _count_path — the counter stub dir plus the suite-wide stubs so an
# ad-hoc `bats` run is as hermetic as a tests/run.sh run.
_count_path() {
  echo "$TEST_TMP/countbin:$ROOT_DIR/tests/helpers/bin"
}

# Per-command timeout (seconds) so a regressing re-capture loop can
# never hang CI — same guard as test_check_modules.bats.
_CMD_TIMEOUT=280

_run_lim() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# _lib_stack — emitted once so every in-process module invocation shares
# the exact source list mdoctor/doctor.sh build before dispatching.
_lib_stack() {
  cat <<'EOS'
  source "$ROOT_DIR/lib/context.sh" && mdoctor_context_init
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/safety.sh"
  source "$ROOT_DIR/lib/perf_probes.sh"
  init_colors
  MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DIR OPLOG_ENABLED=false
EOS
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-capture-once.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/countbin" "$TEST_TMP/count" "$TEST_TMP/home"

  # Resolve the real cat BEFORE the stub dir can shadow it.
  local real_cat
  real_cat="$(command -v cat || echo /bin/cat)"

  # --- argv-logging stubs for the counted slow binaries --------------
  # Each appends "<name> <argv>" to $MDOCTOR_COUNT_LOG, then prints a
  # realistic report so the in-shell parsers exercise their real paths.
  cat >"$TEST_TMP/countbin/system_profiler" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'system_profiler %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
case "$*" in
  *SPPowerDataType*)
    if [ -n "${MDOCTOR_STUB_NOBATT:-}" ]; then
      printf '%s\n' 'Power:' '' '    AC Charger Information:' '      Connected: Yes' '      Charging: No'
    else
      printf '%s\n' 'Power:' '' '    Battery Information:' '' '      Charge Information:' '        Charge Remaining (mAh): 5123' '        Fully Charged: No' '        Charging: No' '      Health Information:' '        Cycle Count: 124' '        Condition: Normal'
    fi
    ;;
  *)
    printf '%s\n' 'Hardware:' '' '    Hardware Overview:' '      Model Name: Mac'
    ;;
esac
EOF
  cat >"$TEST_TMP/countbin/ioreg" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'ioreg %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
printf '%s\n' '    "AppleRawMaxCapacity" = 953' '    "DesignCapacity" = 1134'
EOF
  cat >"$TEST_TMP/countbin/pmset" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'pmset %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
printf '%s\n' "Now drawing from 'Battery Power'" ' -InternalBattery-0 (id=4567)	82%; discharging; 3:12 remaining present: true'
EOF
  cat >"$TEST_TMP/countbin/vm_stat" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'vm_stat %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
printf '%s\n' 'Mach Virtual Memory Statistics: (page size of 16384 bytes)' 'Pages active:                              120000.' 'Pages inactive:                             40000.' 'Pages wired down:                           30000.' 'Pages swapped in:                               0.' 'Pages swapped out:                              0.'
EOF
  cat >"$TEST_TMP/countbin/nproc" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'nproc %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
printf '8\n'
EOF
  cat >"$TEST_TMP/countbin/dpkg" <<'EOF'
#!/bin/sh
[ -n "${MDOCTOR_COUNT_LOG:-}" ] && printf 'dpkg %s\n' "$*" >>"$MDOCTOR_COUNT_LOG"
case "$*" in
  "-l"|"-l "*)
    printf '%s\n' \
      'Desired=Unknown/Install/Remove/Purge/Hold' \
      '| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend' \
      '||/ Name                    Version                  Architecture Description' \
      '+++-=======================-=========================-============-============' \
      'ii  adduser                 3.137                    all          add and remove users' \
      'rc  oldpkg                  1.0                      amd64        removed residual config' \
      'ii  unattended-upgrades     2.9                      all          automatic security upgrades'
    ;;
esac
EOF
  # cat logs its argv then delegates to the real binary — this is how
  # /proc/meminfo and /proc/loadavg read-once are counted.
  cat >"$TEST_TMP/countbin/cat" <<EOF
#!/bin/sh
[ -n "\${MDOCTOR_COUNT_LOG:-}" ] && printf 'cat %s\n' "\$*" >>"\$MDOCTOR_COUNT_LOG"
exec ${real_cat} "\$@"
EOF

  # --- silent stubs for slow/hang-prone probes the counted run passes -
  for _s in apt-get apt-mark; do
    printf '#!/bin/sh\nexit 0\n' >"$TEST_TMP/countbin/$_s"
  done
  for _s in ping nslookup ss softwareupdate systemctl ufw mdfind; do
    printf '#!/bin/sh\nexit 1\n' >"$TEST_TMP/countbin/$_s"
  done
  # ps: argv-dispatching fixture (same shape as test_perf_probes.bats).
  # Every table needs >6 data lines: the consumers run head -6 | tail -5
  # to drop the header, and a shorter table would leak the "PID RSS
  # COMMAND" header into the arithmetic parser (set -u trips on it).
  cat >"$TEST_TMP/countbin/ps" <<'EOF'
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
  chmod +x "$TEST_TMP/countbin/"*
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

@test "each slow report has exactly one capture call site" {
  # battery.sh: one invocation line per slow binary (comments excluded;
  # the *_out capture variables name-drop the tool, so count the $(...)
  # call itself, not the bare name).
  local b="$ROOT_DIR/checks/battery.sh"
  [ "$(grep -vE '^\s*#' "$b" | grep -cF '$(system_profiler' || true)" = "1" ] \
    || fail "battery.sh must invoke system_profiler exactly once"
  [ "$(grep -vE '^\s*#' "$b" | grep -cF '$(ioreg' || true)" = "1" ] \
    || fail "battery.sh must invoke ioreg exactly once"
  [ "$(grep -vE '^\s*#' "$b" | grep -cF '$(pmset' || true)" = "1" ] \
    || fail "battery.sh must invoke pmset exactly once"

  # No module invokes `dpkg -l` directly anymore — every consumer reads
  # the shared perf_capture_dpkg_l snapshot. (The apt add_action text
  # carries a literal escaped '\$(dpkg -l ...)' suggestion — excluded.)
  local raw
  raw="$(grep -vE '^\s*#' "$ROOT_DIR/checks/apt.sh" "$ROOT_DIR/checks/apps.sh" \
    "$ROOT_DIR/checks/security.sh" | grep -F 'dpkg -l' | grep -vcF '\$(dpkg -l' || true)"
  [ "$raw" = "0" ] || fail "found $raw direct 'dpkg -l' invocations outside lib/perf_probes.sh"
  grep -q 'perf_capture_dpkg_l' "$ROOT_DIR/checks/apt.sh" \
    || fail "check_apt must read the shared dpkg -l snapshot"
  grep -q 'perf_capture_dpkg_l' "$ROOT_DIR/checks/apps.sh" \
    || fail "check_apps must read the shared dpkg -l snapshot"
  grep -q 'perf_capture_dpkg_l' "$ROOT_DIR/checks/security.sh" \
    || fail "check_security must read the shared dpkg -l snapshot"

  # vm_stat / nproc / direct /proc reads exist only behind the samplers
  # in lib/perf_probes.sh — no module forks them itself (`command -v`
  # presence guards are capability probes, not report captures).
  local vms nps
  vms="$(grep -vE '^\s*#' "$ROOT_DIR"/checks/*.sh "$ROOT_DIR/mdoctor" "$ROOT_DIR/doctor.sh" \
    | grep -v 'perf_capture_vm_stat' | grep -v 'command -v' | grep -c 'vm_stat' || true)"
  [ "$vms" = "0" ] || fail "found $vms direct vm_stat invocations outside the sampler"
  nps="$(grep -vE '^\s*#' "$ROOT_DIR"/checks/*.sh "$ROOT_DIR/mdoctor" "$ROOT_DIR/doctor.sh" \
    | grep -v 'perf_capture_nproc' | grep -v 'command -v' | grep -c 'nproc' || true)"
  [ "$nps" = "0" ] || fail "found $nps direct nproc invocations outside the sampler"

  # /proc/meminfo and /proc/loadavg are opened only inside
  # lib/perf_probes.sh — '-r' readability guards are not reads.
  local reads
  reads="$(grep -vE '^\s*#' "$ROOT_DIR"/checks/*.sh "$ROOT_DIR/mdoctor" "$ROOT_DIR/doctor.sh" \
    | grep -cE 'cat /proc/meminfo|< */proc/meminfo|cat /proc/loadavg|< */proc/loadavg' || true)"
  [ "$reads" = "0" ] || fail "found $reads direct /proc reads outside the samplers"
}

@test "battery check invokes system_profiler, ioreg and pmset exactly once" {
  local log="$TEST_TMP/count/battery.log"
  : >"$log"
  # Forced-macOS in-process run: the registry never dispatches battery
  # on Linux, so the module is invoked directly under a pinned platform
  # with the counter stubs on PATH — no real macOS binary is reached.
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" ROOT_DIR="$ROOT_DIR" \
    bash -c '
      '"$(_lib_stack)"'
      export MDOCTOR_PLATFORM=macos
      source "$ROOT_DIR/checks/battery.sh"
      check_battery' >"$TEST_TMP/count/battery.out" 2>&1 \
    || fail "check_battery exited non-zero under stubs"
  [ "$(_count_log "$log" 'system_profiler SPPowerDataType')" = "1" ] \
    || fail "system_profiler SPPowerDataType != 1: $(cat "$log")"
  [ "$(_count_log "$log" 'ioreg')" = "1" ] \
    || fail "ioreg != 1: $(cat "$log")"
  [ "$(_count_log "$log" 'pmset -g batt')" = "1" ] \
    || fail "pmset -g batt != 1: $(cat "$log")"

  # The single captures still feed every field (in-shell parse proof).
  strip_ansi "$TEST_TMP/count/battery.out" >"$TEST_TMP/count/battery.txt"
  assert_contains "$TEST_TMP/count/battery.txt" "Battery condition: Normal"
  assert_contains "$TEST_TMP/count/battery.txt" "Battery cycle count: 124"
  assert_contains "$TEST_TMP/count/battery.txt" "Battery health: 84%"
  assert_contains "$TEST_TMP/count/battery.txt" "Power source: Battery Power"
  assert_contains "$TEST_TMP/count/battery.txt" "Battery: 82% (discharging)"
}

@test "battery desktop path still captures the power report exactly once" {
  local log="$TEST_TMP/count/battery_nb.log"
  : >"$log"
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" MDOCTOR_STUB_NOBATT=1 ROOT_DIR="$ROOT_DIR" \
    bash -c '
      '"$(_lib_stack)"'
      export MDOCTOR_PLATFORM=macos
      source "$ROOT_DIR/checks/battery.sh"
      check_battery' >"$TEST_TMP/count/battery_nb.out" 2>&1 \
    || fail "check_battery (no-battery) exited non-zero under stubs"
  [ "$(_count_log "$log" 'system_profiler SPPowerDataType')" = "1" ] \
    || fail "system_profiler SPPowerDataType != 1: $(cat "$log")"
  [ "$(_count_log "$log" 'ioreg')" = "0" ] \
    || fail "ioreg ran on the no-battery early return: $(cat "$log")"
  [ "$(_count_log "$log" 'pmset')" = "0" ] \
    || fail "pmset ran on the no-battery early return: $(cat "$log")"
  strip_ansi "$TEST_TMP/count/battery_nb.out" >"$TEST_TMP/count/battery_nb.txt"
  assert_contains "$TEST_TMP/count/battery_nb.txt" "No battery detected"
}

@test "one dpkg -l snapshot serves apt, apps and security in a run" {
  local log="$TEST_TMP/count/dpkg.log"
  : >"$log"
  # Forced Debian-family: the three historical consumers run in one
  # process — the first capture must serve all of them.
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" ROOT_DIR="$ROOT_DIR" \
    bash -c '
      '"$(_lib_stack)"'
      export MDOCTOR_PLATFORM=linux MDOCTOR_DISTRO=debian
      source "$ROOT_DIR/checks/apt.sh"
      source "$ROOT_DIR/checks/apps.sh"
      source "$ROOT_DIR/checks/security.sh"
      check_apt
      check_apps
      check_security' >"$TEST_TMP/count/dpkg.out" 2>&1 \
    || fail "Debian check modules exited non-zero under stubs"
  [ "$(_count_log "$log" 'dpkg -l')" = "1" ] \
    || fail "dpkg -l != 1 across apt+apps+security: $(cat "$log")"
  strip_ansi "$TEST_TMP/count/dpkg.out" >"$TEST_TMP/count/dpkg.txt"
  assert_contains "$TEST_TMP/count/dpkg.txt" "Installed packages: 2"
  assert_contains "$TEST_TMP/count/dpkg.txt" "Unattended upgrades: installed"
}

@test "capture samplers memoize: repeat calls replay one read per run" {
  local log="$TEST_TMP/count/probes.log"
  : >"$log"
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" ROOT_DIR="$ROOT_DIR" \
    bash -c '
      source "$ROOT_DIR/lib/platform.sh"
      source "$ROOT_DIR/lib/perf_probes.sh"
      # Each sampler called twice: the second call must replay.
      perf_capture_nproc || true;  perf_capture_nproc || true
      perf_capture_vm_stat || true; perf_capture_vm_stat || true
      perf_capture_dpkg_l || true;  perf_capture_dpkg_l || true
      # Load probe twice: one nproc + one /proc/loadavg serve both.
      perf_probe_load >/dev/null 2>&1 || true
      perf_probe_load >/dev/null 2>&1 || true
      # Three meminfo consumers — pressure + swap + a direct capture —
      # share the one read; the swap record is derived once, not twice.
      perf_capture_meminfo || true
      perf_probe_mem_pressure >/dev/null 2>&1 || true
      perf_probe_swap >/dev/null 2>&1 || true
      perf_probe_swap >/dev/null 2>&1 || true
      # perf_capture_reset re-arms every sampler: one fresh read each.
      perf_capture_reset
      perf_capture_nproc || true
      perf_capture_vm_stat || true
      perf_capture_dpkg_l || true
      perf_probe_load >/dev/null 2>&1 || true
      perf_capture_meminfo || true' 2>/dev/null \
    || fail "capture samplers exited non-zero under stubs"
  [ "$(_count_log "$log" 'nproc')" = "2" ] \
    || fail "nproc != 2 (once per capture epoch): $(cat "$log")"
  [ "$(_count_log "$log" 'vm_stat')" = "2" ] \
    || fail "vm_stat != 2 (once per capture epoch): $(cat "$log")"
  [ "$(_count_log "$log" 'dpkg -l')" = "2" ] \
    || fail "dpkg -l != 2 (once per capture epoch): $(cat "$log")"
  if is_linux; then
    [ "$(_count_log "$log" 'cat /proc/meminfo')" = "2" ] \
      || fail "/proc/meminfo != 2 (once per epoch for all consumers): $(cat "$log")"
    [ "$(_count_log "$log" 'cat /proc/loadavg')" = "2" ] \
      || fail "/proc/loadavg != 2 (once per epoch): $(cat "$log")"
  else
    # No /proc on macOS: the samplers must not touch cat at all here.
    [ "$(_count_log "$log" 'cat /proc/')" = "0" ] \
      || fail "unexpected /proc reads on macOS: $(cat "$log")"
  fi
}

@test "full mdoctor check reads each captured report at most once" {
  local log="$TEST_TMP/count/check.log"
  : >"$log"
  local rc=0
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" \
    _run_lim ./mdoctor check >"$TEST_TMP/count/check.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -n 20 "$TEST_TMP/count/check.out" >&2 || true
    fail "'mdoctor check' exited $rc under stubs (expected 0)"
  fi
  # Universal bound: at most one capture of each slow report per run.
  local c_sp c_ioreg c_pmset c_dpkg c_nproc c_vmstat
  c_sp="$(_count_log "$log" 'system_profiler SPPowerDataType')"
  c_ioreg="$(_count_log "$log" 'ioreg')"
  c_pmset="$(_count_log "$log" 'pmset -g batt')"
  c_dpkg="$(_count_log "$log" 'dpkg -l')"
  c_nproc="$(_count_log "$log" 'nproc')"
  c_vmstat="$(_count_log "$log" 'vm_stat')"
  [ "$c_sp" -le 1 ]    || fail "system_profiler SPPowerDataType ran ${c_sp}x: $(cat "$log")"
  [ "$c_ioreg" -le 1 ] || fail "ioreg ran ${c_ioreg}x: $(cat "$log")"
  [ "$c_pmset" -le 1 ] || fail "pmset -g batt ran ${c_pmset}x: $(cat "$log")"
  [ "$c_dpkg" -le 1 ]  || fail "dpkg -l ran ${c_dpkg}x: $(cat "$log")"
  [ "$c_nproc" -le 1 ] || fail "nproc ran ${c_nproc}x: $(cat "$log")"
  [ "$c_vmstat" -le 1 ] || fail "vm_stat ran ${c_vmstat}x: $(cat "$log")"
  # Platform-exact: on the host's own lane the captures provably fired.
  if is_linux; then
    [ "$c_dpkg" = "1" ]  || fail "dpkg -l must fire once on Linux: $(cat "$log")"
    [ "$c_nproc" = "1" ] || fail "nproc must fire once on Linux: $(cat "$log")"
    [ "$(_count_log "$log" 'cat /proc/meminfo')" = "1" ] \
      || fail "/proc/meminfo must be read once on Linux: $(cat "$log")"
    [ "$(_count_log "$log" 'cat /proc/loadavg')" = "1" ] \
      || fail "/proc/loadavg must be read once on Linux: $(cat "$log")"
  else
    [ "$c_sp" = "1" ]    || fail "system_profiler SPPowerDataType must fire once on macOS: $(cat "$log")"
    [ "$c_ioreg" = "1" ] || fail "ioreg must fire once on macOS: $(cat "$log")"
    [ "$c_pmset" = "1" ] || fail "pmset -g batt must fire once on macOS: $(cat "$log")"
    [ "$c_vmstat" = "1" ] || fail "vm_stat must fire once on macOS: $(cat "$log")"
  fi
}

@test "mdoctor diagnose samples each captured input at most once" {
  local log="$TEST_TMP/count/diagnose.log"
  : >"$log"
  local rc=0
  PATH="$(_count_path):$PATH" HOME="$TEST_TMP/home" \
    MDOCTOR_COUNT_LOG="$log" \
    DIAG_LOADAVG="0.10" DIAG_CORES="8" DIAG_MEM_PCT="10" \
    DIAG_MEM_AVAIL_PCT="80" DIAG_MEM_PRESSURE_LEVEL="1" \
    DIAG_DISK_PCT="20" DIAG_SWAP_PCT="0" DIAG_LINUX_IOWAIT_PCT="0" \
    DIAG_CPU_USER_PCT="10" DIAG_CPU_SYS_PCT="5" \
    _run_lim ./mdoctor diagnose >"$TEST_TMP/count/diagnose.out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -n 20 "$TEST_TMP/count/diagnose.out" >&2 || true
    fail "'mdoctor diagnose' exited $rc under stubs (expected 0)"
  fi
  # vm_stat fires once on every platform: the diagnose prefill captures
  # it unconditionally whenever the binary exists (stubbed here).
  [ "$(_count_log "$log" 'vm_stat')" = "1" ] \
    || fail "vm_stat != 1 in diagnose: $(cat "$log")"
  [ "$(_count_log "$log" 'nproc')" -le 1 ] \
    || fail "nproc ran more than once in diagnose: $(cat "$log")"
  [ "$(_count_log "$log" 'cat /proc/meminfo')" -le 1 ] \
    || fail "/proc/meminfo read more than once in diagnose: $(cat "$log")"
  [ "$(_count_log "$log" 'cat /proc/loadavg')" -le 1 ] \
    || fail "/proc/loadavg read more than once in diagnose: $(cat "$log")"
  if is_linux; then
    [ "$(_count_log "$log" 'nproc')" = "1" ] \
      || fail "nproc must fire once on Linux diagnose: $(cat "$log")"
    [ "$(_count_log "$log" 'cat /proc/meminfo')" = "1" ] \
      || fail "/proc/meminfo must be read once on Linux diagnose: $(cat "$log")"
    [ "$(_count_log "$log" 'cat /proc/loadavg')" = "1" ] \
      || fail "/proc/loadavg must be read once on Linux diagnose: $(cat "$log")"
  fi
}
