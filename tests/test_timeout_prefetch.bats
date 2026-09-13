#!/usr/bin/env bats
#
# test_timeout_prefetch.bats
# Issue #101 (Task 11.7, M4): every blocking network/daemon call is
# time-capped via lib/timeout.sh's portable wrapper, a timed-out call
# reports a distinct "timed out" status instead of collapsing into an
# empty/success result, the run's `docker info` probe is captured once
# for both consumers, and the independent registry/daemon probes run in
# parallel behind perf_prefetch_begin's lazy joins.
#
# Conventions: same fixture root + stub-PATH pattern as
# test_check_missing_probes.bats; stubs log their argv to
# $MDOCTOR_STUB_LOG so tests can count invocations.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-timeout.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/home"
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

# _load_stack — source the same lib stack doctor.sh loads, in order.
_load_stack() {
  source "$ROOT_DIR/lib/context.sh"
  mdoctor_context_init
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"   # step()/status_* call md_append
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/perf_probes.sh"
}

# perf_prefetch_begin registers perf_prefetch_cleanup on the process's
# EXIT trap — installing a trap inside a @test process would replace
# bats' own teardown bookkeeping and the test would never report. The
# prefetch tests below shadow the registry with a no-op (and call
# perf_prefetch_cleanup explicitly).

# _write_stub DIR NAME BODY... — one executable stub; "$@" body lines.
_write_stub() {
  local dir="$1" name="$2"
  shift 2
  printf '#!/usr/bin/env bash\n' >"$dir/$name"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >>"$dir/$name"
  done
  chmod +x "$dir/$name"
}

# _make_dockbin DIR — argv-logging docker + quiet npm/pip3 stubs so the
# prefetch never touches a real registry (a host npm would otherwise run
# a genuine `npm doctor`).
_make_dockbin() {
  local dir="$1"
  mkdir -p "$dir"
  _write_stub "$dir" docker \
    'printf "docker %s\n" "$*" >>"$MDOCTOR_STUB_LOG"' \
    'case " $* " in *" info "*) echo "Server Version: 99" ;; esac' \
    'exit 0'
  _write_stub "$dir" npm 'exit 0'
  _write_stub "$dir" pip3 'exit 0'
}

# --- 1. rc passthrough ------------------------------------------------

@test "mdoctor_timeout: fast command passes through output and exit code" {
  source "$ROOT_DIR/lib/timeout.sh"
  local out rc=0
  out="$(mdoctor_timeout 5 printf 'hello')"
  [ "$out" = "hello" ]
  mdoctor_timeout 5 sh -c 'exit 7' >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 7 ]
}

# --- 2. distinct 124 on both backends ---------------------------------

@test "mdoctor_timeout: cap fires → rc 124 (auto backend)" {
  source "$ROOT_DIR/lib/timeout.sh"
  local rc=0
  SECONDS=0
  mdoctor_timeout 1 sleep 30 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 124 ]
  [ "$SECONDS" -lt 10 ]
}

@test "mdoctor_timeout: watchdog backend returns 124 without GNU timeout" {
  source "$ROOT_DIR/lib/timeout.sh"
  local rc=0
  SECONDS=0
  MDOCTOR_TIMEOUT_IMPL=watchdog mdoctor_timeout 1 sleep 30 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 124 ]
  [ "$SECONDS" -lt 10 ]
}

@test "mdoctor_timeout: TERM-ignoring probe is KILLed inside the grace" {
  source "$ROOT_DIR/lib/timeout.sh"
  local rc=0
  SECONDS=0
  # The probe ignores TERM; both backends must hard-kill ~1s past the cap.
  MDOCTOR_TIMEOUT_IMPL=watchdog \
    mdoctor_timeout 1 sh -c 'trap "" TERM; exec sleep 30' >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 124 ]
  [ "$SECONDS" -lt 10 ]
}

@test "mdoctor_timeout: non-numeric and zero caps run the command directly" {
  source "$ROOT_DIR/lib/timeout.sh"
  local out rc=0
  out="$(mdoctor_timeout 0 printf 'direct')"
  [ "$out" = "direct" ]
  out="$(mdoctor_timeout bogus printf 'direct2')"
  [ "$out" = "direct2" ]
  mdoctor_timeout 0 sh -c 'exit 9' >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 9 ]
}

# --- 3. distinct "timed out" reporting --------------------------------

@test "tcap: a timed-out probe prints a distinct line and leaves _TCAP_OUT empty" {
  _load_stack
  local rc=0
  tcap 1 "Slow probe" sleep 30 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 124 ]
  [ -z "$_TCAP_OUT" ]
}

@test "tcap_or: 124 surfaces as 'timed out' text, other failures as fallback" {
  _load_stack
  local v
  v="$(tcap_or 1 "fallback" sleep 30)"
  [ "$v" = "timed out (timeout 1s)" ]
  v="$(tcap_or 5 "fallback" sh -c 'exit 3')"
  [ "$v" = "fallback" ]
  v="$(tcap_or 5 "fallback" printf 'real')"
  [ "$v" = "real" ]
}

@test "check_node_npm: a hanging npm doctor reports 'timed out', never silently" {
  _load_stack
  source "$ROOT_DIR/checks/node.sh"
  mkdir -p "$TEST_TMP/hangbin"
  _write_stub "$TEST_TMP/hangbin" npm \
    'printf "npm %s\n" "$*" >>"$MDOCTOR_STUB_LOG"' \
    'case " $* " in *" -v "*) echo "10.9.0"; exit 0 ;; *) sleep 30 ;; esac'
  local out rc=0
  out=$(PATH="$TEST_TMP/hangbin:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/hang.log" \
        MDOCTOR_REGISTRY_TIMEOUT_S=1 check_node_npm 2>&1) || rc=$?
  [ "$rc" -eq 0 ]
  case "$out" in
    *"npm doctor timed out"*) ;;
    *) fail "expected a distinct 'npm doctor timed out' line, got: ${out:-<nothing>}" ;;
  esac
}

# --- 4. docker info captured once --------------------------------------

@test "docker info probe runs once for check_dev_tools + check_containers" {
  _load_stack
  source "$ROOT_DIR/checks/devtools.sh"
  source "$ROOT_DIR/checks/containers.sh"
  _make_dockbin "$TEST_TMP/dockbin"
  : >"$TEST_TMP/dock.log"
  register_exit_hook() { :; }   # keep bats' EXIT trap intact
  PATH="$TEST_TMP/dockbin:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/dock.log" \
    perf_prefetch_begin
  PATH="$TEST_TMP/dockbin:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/dock.log" \
    check_dev_tools >/dev/null 2>&1
  PATH="$TEST_TMP/dockbin:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/dock.log" \
    check_containers >/dev/null 2>&1
  perf_prefetch_cleanup
  local info_calls
  info_calls=$(grep -c '^docker info$' "$TEST_TMP/dock.log" || true)
  [ "$info_calls" = "1" ]
}

@test "docker info probe runs once even without the prefetch" {
  _load_stack
  source "$ROOT_DIR/checks/devtools.sh"
  source "$ROOT_DIR/checks/containers.sh"
  _make_dockbin "$TEST_TMP/dockbin2"
  : >"$TEST_TMP/dock2.log"
  # No perf_prefetch_begin: lazy joins fall back to inline probes, and
  # the shared capture still keeps `docker info` to a single call.
  PATH="$TEST_TMP/dockbin2:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/dock2.log" \
    MDOCTOR_PREFETCH=false check_dev_tools >/dev/null 2>&1
  PATH="$TEST_TMP/dockbin2:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/dock2.log" \
    MDOCTOR_PREFETCH=false check_containers >/dev/null 2>&1
  local info_calls
  info_calls=$(grep -c '^docker info$' "$TEST_TMP/dock2.log" || true)
  [ "$info_calls" = "1" ]
}

# --- 5. socket enumerator runs once ------------------------------------

@test "check_open_connections samples the socket table exactly once" {
  _load_stack
  source "$ROOT_DIR/checks/diagnose_performance.sh"
  ACTIONS=() ACTIONS_CRITICAL=() ACTIONS_WARNING=()
  mkdir -p "$TEST_TMP/sockbin"
  local enum_name enum_output
  if is_macos; then
    enum_name=netstat
    # netstat -an shape: proto, addr cols, state last.
    enum_output='tcp4 0 0 127.0.0.1.80 *.* LISTEN\ntcp4 0 0 10.0.0.2.22 10.0.0.1.5 ESTABLISHED'
  else
    enum_name=ss
    # ss -tun shape: state col after header.
    enum_output='Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port\ntcp ESTAB 0 0 10.0.0.2:22 10.0.0.1:5\ntcp LISTEN 0 128 0.0.0.0:80 0.0.0.0:*'
  fi
  _write_stub "$TEST_TMP/sockbin" "$enum_name" \
    'printf "enum %s\n" "$0" >>"$MDOCTOR_STUB_LOG"' \
    "printf '${enum_output}\\n'"
  : >"$TEST_TMP/sock.log"
  PATH="$TEST_TMP/sockbin:$PATH" MDOCTOR_STUB_LOG="$TEST_TMP/sock.log" \
    check_open_connections >/dev/null 2>&1
  local enum_calls
  enum_calls=$(wc -l <"$TEST_TMP/sock.log" | tr -d ' ')
  [ "$enum_calls" = "1" ]
}

# --- 6. parallel prefetch beats the sequential sum --------------------

@test "independent probes prefetch in parallel (2s stubs finish below the sum)" {
  _load_stack
  mkdir -p "$TEST_TMP/slowbin"
  # Each probe sleeps 2s. On Linux the list is npm×2 + pip3×2 + docker×1
  # (5 probes → 10s sequential); on macOS brew×2 + softwareupdate×1 swap
  # in for the pip3 pair — same shape.
  local tool
  for tool in npm pip3 docker brew softwareupdate; do
    _write_stub "$TEST_TMP/slowbin" "$tool" \
      'sleep 2' \
      'printf "%s-ok\n" "$(basename "$0")"'
  done
  local rc=0 start elapsed
  start=$SECONDS
  register_exit_hook() { :; }   # keep bats' EXIT trap intact
  PATH="$TEST_TMP/slowbin:$PATH" perf_prefetch_begin
  # Lazy joins — subshell consumers poll result files (the same path
  # check-modules take via $( perf_probe_out ... )).
  local nd no pc po di=""
  nd=$(perf_probe_out npm_doctor)
  no=$(perf_probe_out npm_outdated)
  pc=$(perf_probe_out pip3_check)
  po=$(perf_probe_out pip3_outdated)
  PATH="$TEST_TMP/slowbin:$PATH" perf_capture_docker_info || true
  di="$_PERF_DOCKER_INFO"
  perf_prefetch_join
  elapsed=$((SECONDS - start))
  # 5 × 2s probes sequentially = 10s; parallel ≈ 2–3s. Bound at 8s leaves
  # CI jitter headroom while still proving the overlap.
  [ "$elapsed" -lt 8 ]
  [ "$nd" = "npm-ok" ]
  [ "$no" = "npm-ok" ]
  [ "$pc" = "pip3-ok" ]
  [ "$po" = "pip3-ok" ]
  [ "$di" = "docker-ok" ]
  perf_prefetch_cleanup
}

@test "prefetched probe keeps its timeout cap and propagates 124" {
  _load_stack
  mkdir -p "$TEST_TMP/hangbin2"
  _write_stub "$TEST_TMP/hangbin2" npm 'sleep 30'
  local out="" rc=0
  register_exit_hook() { :; }   # keep bats' EXIT trap intact
  PATH="$TEST_TMP/hangbin2:$PATH" MDOCTOR_REGISTRY_TIMEOUT_S=1 perf_prefetch_begin
  out=$(PATH="$TEST_TMP/hangbin2:$PATH" MDOCTOR_REGISTRY_TIMEOUT_S=1 \
        perf_probe_out npm_doctor) || rc=$?
  [ "$rc" -eq 124 ]
  [ -z "$out" ]
  perf_prefetch_cleanup
}

# --- 7. census: zero uncapped named call sites --------------------------

@test "issue #101 census: every named blocking site mentions timeout" {
  local uncapped
  # `grep -vc` exits 1 on a zero count (it still prints "0") — the
  # `|| true` keeps the substitution from aborting the test under errexit.
  uncapped=$(cd "$ROOT_DIR" && grep -rn \
    'npm \|brew \|docker info\|nslookup\|apt list\|softwareupdate\|du -sk' \
    checks/ lib/ | grep -vc timeout || true)
  [ "$uncapped" = "0" ]
}
