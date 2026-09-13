#!/usr/bin/env bats
#
# test_numeric_validation.bats
# Issue #111 (Task 12.8): numeric readings from external commands are
# validated (^[0-9]+$ via is_uint) before arithmetic — an empty or
# unparseable value reports "could not determine" instead of silently
# coercing to 0 and printing a healthy summary. Companion honesty fixes
# in the same issue: net_drops reads the Oerrs column on the row matched
# by interface name (never a fixed NR==2 position), fix_dns fails when
# no resolver tool exists, the thermal zone is picked by its `type`
# file, systemd reachability is probed before counting services,
# lib/metadata.sh survives re-sourcing, and VERSION_ID is defaulted
# before the suffix strip in lib/platform.sh.
#
# Hermetic by construction: PATH stubs (df, sysctl, vm_stat, cat,
# netstat, systemctl, route, ping, nslookup, curl, scutil, ipconfig),
# a sparse farm without the resolver tools, MDOCTOR_THERMAL_ROOT /
# MDOCTOR_OS_RELEASE fixture roots, sandboxed HOME. Bash 3.2 compatible.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

# The library env a check module expects, as the mdoctor engine provides.
# Sourced inside each `bash -c` driver below (each test's subshell gets a
# fresh, un-cached capture state — the perf_capture_* records memoize per
# process, so no two check runs may share one shell).
_check_env() {
  cat <<'ENV'
    source "$ROOT_DIR/lib/context.sh"; mdoctor_context_init
    source "$ROOT_DIR/lib/platform.sh"
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/logging.sh"
    source "$ROOT_DIR/lib/safety.sh"
    init_colors
    export MDOCTOR_DIR="$ROOT_DIR" OPLOG_ENABLED=false
    source "$ROOT_DIR/lib/disk.sh"
    source "$ROOT_DIR/lib/perf_probes.sh"
ENV
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP FIXTURE_ROOT
  FIXTURE_ROOT="$(fixture_root)"
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-numval.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"

  # --- cat stub: /proc/* reads answer empty, everything else execs the
  # real binary. Empties the capture-once snapshots deterministically on
  # every host (a macOS lane has no /proc at all — same outcome). ---
  REAL_CAT="$(command -v cat 2>/dev/null || echo /bin/cat)"
  export REAL_CAT
  mkdir -p "$TEST_TMP/catbin"
  cat >"$TEST_TMP/catbin/cat" <<EOF
#!/usr/bin/env bash
case "\$1" in
  /proc/*) exit 0 ;;
  *) exec "$REAL_CAT" "\$@" ;;
esac
EOF
  chmod +x "$TEST_TMP/catbin/cat"

  # --- Empty-probe stubs: df/sysctl/vm_stat answer rc 0 with no output ---
  mkdir -p "$TEST_TMP/emptybin"
  for _t in df sysctl vm_stat; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TEST_TMP/emptybin/$_t"
    chmod +x "$TEST_TMP/emptybin/$_t"
  done

  # --- Sparse farm without the DNS resolver tools (fix_dns lane): every
  # host binary except resolvectl/systemd-resolve, same pattern as
  # test_check_missing_probes.bats. ---
  mkdir -p "$TEST_TMP/farm"
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        resolvectl|systemd-resolve) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  # Keep the farm executable on minimal images (same reasoning as the
  # missing-probes farm).
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

# ---------------------------------------------------------------------
# is_uint — the shared ^[0-9]+$ gate (issue #111)
# ---------------------------------------------------------------------

@test "is_uint accepts digits and rejects empty/non-numeric" {
  bash -c '
    source "$ROOT_DIR/lib/constants.sh"
    is_uint "0" && is_uint "42" && is_uint "007" || exit 10
    ! is_uint "" && ! is_uint "abc" && ! is_uint "1.5" && ! is_uint "-3" || exit 20
    v="-7"; is_uint "${v#-}" || exit 30   # signed-strip idiom
  ' || fail "is_uint misclassified a value"
}

# ---------------------------------------------------------------------
# checks/disk.sh — empty/unparseable df must not coerce to 0 (issue #111)
# ---------------------------------------------------------------------

@test "disk check reports 'could not determine' when df prints nothing" {
  local t="$TEST_TMP/df-empty"
  mkdir -p "$t/home"
  PATH="$TEST_TMP/emptybin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    source "$ROOT_DIR/checks/disk.sh"
    check_disk' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_disk exited non-zero"; }
  assert_contains "$t/out.txt" "Disk usage: could not determine"
  assert_not_contains "$t/out.txt" "healthy range"
}

@test "disk check reports 'could not determine' when df prints garbage" {
  local t="$TEST_TMP/df-garbage"
  mkdir -p "$t/bin" "$t/home"
  cat >"$t/bin/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem Size Used Avail Use%% Mounted on\n'
printf '/dev/disk1s1 notanum x y bogus%% /\n'
EOF
  chmod +x "$t/bin/df"
  PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    source "$ROOT_DIR/checks/disk.sh"
    check_disk' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_disk exited non-zero"; }
  assert_contains "$t/out.txt" "Disk usage: could not determine"
  assert_not_contains "$t/out.txt" "healthy range"
}

# ---------------------------------------------------------------------
# checks/system.sh — empty sysctl/vm_stat / /proc reads (issue #111)
# ---------------------------------------------------------------------

@test "system check reports 'could not determine' when sysctl and vm_stat are empty" {
  local t="$TEST_TMP/sys-macos"
  mkdir -p "$t/home"
  # Platform is pinned AFTER lib/platform.sh loads — it re-derives
  # MDOCTOR_PLATFORM from OSTYPE at source time, so an env prefix alone
  # would be overwritten (same reason fix_lane_as_macos exists).
  PATH="$TEST_TMP/emptybin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=macos
    source "$ROOT_DIR/checks/system.sh"
    check_system' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_system exited non-zero"; }
  assert_contains "$t/out.txt" "Memory usage: could not determine"
  assert_not_contains "$t/out.txt" "Memory total: 0"
}

@test "system check reports 'could not determine' when /proc/meminfo is empty" {
  local t="$TEST_TMP/sys-linux"
  mkdir -p "$t/home"
  PATH="$TEST_TMP/catbin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/system.sh"
    check_system' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_system exited non-zero"; }
  assert_contains "$t/out.txt" "Memory usage: could not determine"
  assert_not_contains "$t/out.txt" "Memory total: 0"
}

# ---------------------------------------------------------------------
# checks/performance.sh — empty /proc reads (issue #111)
# ---------------------------------------------------------------------

@test "performance check reports 'could not determine' when /proc reads are empty" {
  local t="$TEST_TMP/perf"
  mkdir -p "$t/home"
  PATH="$TEST_TMP/catbin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/performance.sh"
    check_performance' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_performance exited non-zero"; }
  assert_contains "$t/out.txt" "Memory pressure: could not determine"
  assert_contains "$t/out.txt" "Swap: could not determine"
  assert_contains "$t/out.txt" "Load average: could not determine"
}

# ---------------------------------------------------------------------
# checks/network.sh — Oerrs by column name, row by interface name (#111)
# ---------------------------------------------------------------------

# Shared macOS-shaped stub dir: route answers en0, every other network
# probe is a fast no-op, netstat prints the fixture on $MDOCTOR_NETSTAT_OUT.
_make_net_stubs() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/route" <<'EOF'
#!/usr/bin/env bash
printf '   route to: default\n  interface: en0\n'
EOF
  cat >"$dir/netstat" <<'EOF'
#!/usr/bin/env bash
cat "$MDOCTOR_NETSTAT_FIXTURE"
EOF
  for _t in ping nslookup curl scutil ipconfig; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/$_t"
    chmod +x "$dir/$_t"
  done
  chmod +x "$dir/route" "$dir/netstat"
}

@test "net_drops reports the Oerrs column, not Opkts" {
  local t="$TEST_TMP/net-oerrs"
  mkdir -p "$t/home"
  _make_net_stubs "$t/bin"
  # Ierrs=3, Opkts=999999, Oerrs=7 — the pre-fix field-8 read reported
  # "drops: 999999".
  cat >"$t/netstat.txt" <<'EOF'
Name  Mtu   Network       Address               Ipkts Ierrs    Ibytes    Opkts Oerrs    Obytes  Coll
en0   1500  <Link#4>      aa:bb:cc:dd:ee:ff     1000     3     50000   999999     7     80000     0
en0   1500  192.168.1.0   192.168.1.42          1000     3     50000   999999     7     80000     0
EOF
  MDOCTOR_NETSTAT_FIXTURE="$t/netstat.txt" \
    PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=macos
    source "$ROOT_DIR/checks/network.sh"
    check_network' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_network exited non-zero"; }
  assert_contains "$t/out.txt" "Network errors on en0: 3"
  assert_contains "$t/out.txt" "Network drops on en0: 7"
  assert_not_contains "$t/out.txt" "999999"
}

@test "net_drops matches the interface row by name, not position" {
  local t="$TEST_TMP/net-byname"
  mkdir -p "$t/home"
  _make_net_stubs "$t/bin"
  # A non-matching row leads the data section (position alone would read
  # its 424242); the en0 row carries the real counters.
  cat >"$t/netstat.txt" <<'EOF'
Name  Mtu   Network       Address               Ipkts Ierrs    Ibytes    Opkts Oerrs    Obytes  Coll
lo0   16384 <Link#1>      00:00:00:00:00:00   424242    11   9999999   424242    55    9999999    0
en0   1500  <Link#4>      aa:bb:cc:dd:ee:ff     1000     0     50000     2000     4     80000     0
EOF
  MDOCTOR_NETSTAT_FIXTURE="$t/netstat.txt" \
    PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=macos
    source "$ROOT_DIR/checks/network.sh"
    check_network' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_network exited non-zero"; }
  assert_contains "$t/out.txt" "Network drops on en0: 4"
  assert_not_contains "$t/out.txt" "424242"
}

@test "net_drops reports 'could not determine' on unparseable counters" {
  local t="$TEST_TMP/net-bad"
  mkdir -p "$t/home"
  _make_net_stubs "$t/bin"
  cat >"$t/netstat.txt" <<'EOF'
Name  Mtu   Network       Address               Ipkts Ierrs    Ibytes    Opkts Oerrs    Obytes  Coll
en0   1500  <Link#4>      aa:bb:cc:dd:ee:ff     1000  bogus    50000     2000  junk     80000     0
EOF
  MDOCTOR_NETSTAT_FIXTURE="$t/netstat.txt" \
    PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=macos
    source "$ROOT_DIR/checks/network.sh"
    check_network' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_network exited non-zero"; }
  assert_contains "$t/out.txt" "could not determine"
}

# ---------------------------------------------------------------------
# fixes/dns.sh — no resolver tool → non-zero, no success claim (#111)
# ---------------------------------------------------------------------

@test "fix dns returns non-zero and never claims success with no resolver tool" {
  local t="$TEST_TMP/dns-none"
  mkdir -p "$t/home"
  local rc=0
  PATH="$TEST_TMP/farm" HOME="$t/home" \
    LOGFILE="$t/home/mdoctor.log" bash -c '
    source "$ROOT_DIR/lib/context.sh"; mdoctor_context_init
    source "$ROOT_DIR/lib/platform.sh"
    export MDOCTOR_PLATFORM=linux   # platform.sh re-derives it at source time
    source "$ROOT_DIR/lib/common.sh"
    source "$ROOT_DIR/lib/logging.sh"
    source "$ROOT_DIR/lib/safety.sh"
    init_colors
    export MDOCTOR_DIR="$ROOT_DIR" OPLOG_ENABLED=false DRY_RUN=false
    source "$ROOT_DIR/fixes/dns.sh"
    fix_dns' >"$t/out.txt" 2>"$t/err.txt" || rc=$?
  [ "$rc" -ne 0 ] || fail "fix_dns succeeded with no resolver tool"
  assert_contains "$t/out.txt" "No systemd-resolved found"
  assert_not_contains "$t/out.txt" "DNS cache flushed."
}

# ---------------------------------------------------------------------
# checks/hardware.sh — thermal zone picked by `type`, temp validated
# ---------------------------------------------------------------------

@test "thermal zone is selected by its type file, not glob order" {
  local t="$TEST_TMP/thermal"
  mkdir -p "$t/home" "$t/sys/thermal_zone0" "$t/sys/thermal_zone1"
  # zone0 (glob-first) is a Wi-Fi sensor, zone1 is the CPU package — the
  # pre-fix break-on-first-readable reported the 95C Wi-Fi reading.
  printf '95000\n' >"$t/sys/thermal_zone0/temp"
  printf 'iwlwifi_1\n'  >"$t/sys/thermal_zone0/type"
  printf '42000\n' >"$t/sys/thermal_zone1/temp"
  printf 'x86_pkg_temp\n' >"$t/sys/thermal_zone1/type"
  MDOCTOR_THERMAL_ROOT="$t/sys" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/hardware.sh"
    check_hardware' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_hardware exited non-zero"; }
  assert_contains "$t/out.txt" "Thermal zone x86_pkg_temp: 42C"
  assert_not_contains "$t/out.txt" "iwlwifi"
  assert_not_contains "$t/out.txt" "95C"
}

@test "thermal probe reports 'could not determine' on a non-numeric reading" {
  local t="$TEST_TMP/thermal-bad"
  mkdir -p "$t/home" "$t/sys/thermal_zone0"
  printf 'garbage\n'        >"$t/sys/thermal_zone0/temp"
  printf 'x86_pkg_temp\n'   >"$t/sys/thermal_zone0/type"
  MDOCTOR_THERMAL_ROOT="$t/sys" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/hardware.sh"
    check_hardware' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_hardware exited non-zero"; }
  assert_contains "$t/out.txt" "could not determine"
}

# ---------------------------------------------------------------------
# checks/startup.sh — systemd reachability probed before counting (#111)
# ---------------------------------------------------------------------

@test "startup check reports 'could not determine' when systemd is unreachable" {
  local t="$TEST_TMP/sc-down"
  mkdir -p "$t/bin" "$t/home"
  cat >"$t/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "System has not been booted with systemd as init system" >&2
exit 1
EOF
  chmod +x "$t/bin/systemctl"
  PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/startup.sh"
    check_startup' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_startup exited non-zero"; }
  assert_contains "$t/out.txt" "could not determine"
  assert_not_contains "$t/out.txt" "Enabled systemd services: 0"
  assert_not_contains "$t/out.txt" "No failed systemd services."
}

@test "startup check counts services when systemd answers" {
  local t="$TEST_TMP/sc-up"
  mkdir -p "$t/bin" "$t/home"
  cat >"$t/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $*" in
  *" --user "*)
    printf 'user-agent.service enabled enabled\n'
    ;;
  *"--failed"*)
    : # zero failed units → empty listing
    ;;
  *"list-unit-files"*)
    printf 'alpha.service enabled enabled\nbeta.service enabled disabled\ngamma.service enabled enabled\n'
    ;;
esac
exit 0
EOF
  chmod +x "$t/bin/systemctl"
  PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/startup.sh"
    check_startup' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_startup exited non-zero"; }
  assert_contains "$t/out.txt" "Enabled systemd services: 3"
  assert_contains "$t/out.txt" "No failed systemd services."
  assert_contains "$t/out.txt" "User-level enabled services: 1"
}

# ---------------------------------------------------------------------
# lib/metadata.sh — double-source guard keeps the registry (issue #111)
# ---------------------------------------------------------------------

@test "metadata registry survives a double source" {
  local t="$TEST_TMP/meta"
  mkdir -p "$t"
  bash -c '
    source "$ROOT_DIR/lib/metadata.sh"
    register_module check demo System SAFE demo_fn "demo module"
    source "$ROOT_DIR/lib/metadata.sh"
    printf "count=%s func=%s loaded=%s\n" \
      "$_MOD_COUNT" "$(get_module_func demo check)" "${_MDOCTOR_METADATA_LOADED}"
  ' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "double-source run exited non-zero"; }
  assert_contains "$t/out.txt" "count=1 func=demo_fn loaded=true"
}

# ---------------------------------------------------------------------
# lib/platform.sh — VERSION_ID defaulted before the suffix strip (#111)
# ---------------------------------------------------------------------

@test "os-release without VERSION_ID sources cleanly under set -u" {
  local t="$TEST_TMP/osrel"
  mkdir -p "$t"
  printf 'ID=noverdistro\nPRETTY_NAME="NoVer Linux"\n' >"$t/os-release"
  MDOCTOR_OS_RELEASE="$t/os-release" bash -u -c '
    OSTYPE=linux-gnu   # force the Linux arm on any host
    source "$ROOT_DIR/lib/platform.sh"
    printf "DISTRO=%s VER=<%s> NAME=%s\n" \
      "$MDOCTOR_DISTRO" "$MDOCTOR_DISTRO_VER" "$MDOCTOR_OS_NAME"
  ' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "platform.sh aborted without VERSION_ID"; }
  assert_not_contains "$t/err.txt" "unbound variable"
  # VER=<>: grep-safe spelling of an empty, defaulted VERSION_ID.
  assert_contains "$t/out.txt" "DISTRO=noverdistro VER=<>"
}

@test "mdoctor help runs with a stub os-release lacking VERSION_ID" {
  local t="$TEST_TMP/osrel-help"
  mkdir -p "$t" "$t/home"
  printf 'ID=noverdistro\nPRETTY_NAME="NoVer Linux"\n' >"$t/os-release"
  local rc=0
  MDOCTOR_OS_RELEASE="$t/os-release" HOME="$t/home" \
    ./mdoctor help >"$t/out.txt" 2>"$t/err.txt" || rc=$?
  [ "$rc" -eq 0 ] || { cat "$t/err.txt" >&2; fail "mdoctor help exited $rc without VERSION_ID"; }
  assert_not_contains "$t/err.txt" "unbound variable"
  assert_contains "$t/out.txt" "Commands"
}

# ---------------------------------------------------------------------
# Post-validation normalization (issue #111, review follow-up): a value
# that PASSES is_uint can still be misread by (( )) — "04096" parses as
# octal and "-08" is an octal error token. Validated readings are forced
# through 10# (signed fields via the sign-strip/10#/reapply idiom).
# ---------------------------------------------------------------------

@test "system check normalizes a zero-padded hw.pagesize before arithmetic" {
  local t="$TEST_TMP/sys-pagesize"
  mkdir -p "$t/bin" "$t/home"
  cat >"$t/bin/sysctl" <<'STUB'
#!/usr/bin/env bash
case "$2" in
  hw.pagesize) echo "04096" ;;
  hw.memsize) echo "34359738368" ;;
  vm.loadavg) echo "{ 1.25 0.97 0.83 }" ;;
  *) exit 1 ;;
esac
STUB
  cat >"$t/bin/vm_stat" <<'STUB'
#!/usr/bin/env bash
cat <<'STAT'
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               20000.
Pages active:                            100000.
Pages inactive:                           50000.
Pages speculative:                         5000.
Pages wired down:                         80000.
STAT
STUB
  chmod +x "$t/bin/sysctl" "$t/bin/vm_stat"
  PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=macos
    source "$ROOT_DIR/checks/system.sh"
    check_system' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_system exited non-zero"; }
  # 230000 pages x 4096 = 898.44 MB used; octal-parsed (2126) it would
  # read ~466 MB — the assert pins the base-10 path.
  assert_contains "$t/out.txt" "used: 898.44 MB"
  assert_not_contains "$t/err.txt" "value too great"
}

@test "iw signal normalizes a zero-padded negative dBm before the threshold" {
  local t="$TEST_TMP/net-sig"
  mkdir -p "$t/home"
  _make_net_stubs "$t/bin"
  cat >"$t/bin/ip" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  route) printf 'default via 192.168.1.1 dev wlan0 proto dhcp metric 600\n' ;;
  link)  printf '1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536\n2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n' ;;
  *)     printf '2: wlan0    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0\n' ;;
esac
STUB
  cat >"$t/bin/iw" <<'STUB'
#!/usr/bin/env bash
printf 'Connected to aa:bb:cc:dd:ee:ff (on wlan0)\n\tSSID: TestNet\n\tsignal: -0100 dBm\n\ttx bitrate: 144.4 MBit/s\n'
STUB
  chmod +x "$t/bin/ip" "$t/bin/iw"
  PATH="$t/bin:$PATH" HOME="$t/home" bash -c '
    '"$(_check_env)"'
    export MDOCTOR_PLATFORM=linux
    source "$ROOT_DIR/checks/network.sh"
    check_network' >"$t/out.txt" 2>"$t/err.txt" \
    || { cat "$t/err.txt" >&2; fail "check_network exited non-zero"; }
  # -0100 is decimal -100 dBm (weak); octal-parsed it is -64 and the
  # raw "-09"-style forms are error tokens — the verdict and a clean
  # stderr together pin the normalized path.
  assert_contains "$t/out.txt" "Wi-Fi signal: -0100 dBm (weak)"
  assert_not_contains "$t/err.txt" "value too great"
}
