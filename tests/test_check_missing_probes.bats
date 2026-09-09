#!/usr/bin/env bats
# Task 2.5: host-binary guards report skips (never errors), and the ping
# timeout is constructed per platform (macOS -W is ms, Linux -W is s).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/checks/network.sh"

_run_lim() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 280 "$@"
  else
    "$@"
  fi
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-probes.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  # --- Unit: ping argv per platform (stub records, never executes) ---
  mkdir -p "$TEST_TMP/stubbin"
  cat >"$TEST_TMP/stubbin/ping" <<'EOF'
#!/usr/bin/env bash
printf 'ping %s\n' "$*" >>"$MDOCTOR_STUB_LOG"
exit 0
EOF
  chmod +x "$TEST_TMP/stubbin/ping"
  # --- Integration: sparse PATH without ping/nslookup/ss/ps ---
  mkdir -p "$TEST_TMP/farm" "$TEST_TMP/home"
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        ping|nslookup|ss|ps) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  # The farm must stay executable on minimal images (Alpine has no
  # /usr/bin/bash) and on macOS (no GNU timeout): link the essentials
  # from the ambient PATH and fall back to running without timeout.
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "ping argv uses seconds on Linux and milliseconds on macOS" {
  : >"$TEST_TMP/ping-linux.log"
  MDOCTOR_STUB_LOG="$TEST_TMP/ping-linux.log" PATH="$TEST_TMP/stubbin:$PATH" \
    MDOCTOR_PLATFORM=linux ping_host 1.1.1.1
  assert_contains "$TEST_TMP/ping-linux.log" "ping -c 1 -W 1 1.1.1.1"

  : >"$TEST_TMP/ping-macos.log"
  MDOCTOR_STUB_LOG="$TEST_TMP/ping-macos.log" PATH="$TEST_TMP/stubbin:$PATH" \
    MDOCTOR_PLATFORM=macos ping_host 1.1.1.1
  assert_contains "$TEST_TMP/ping-macos.log" "ping -c 1 -W 1000 1.1.1.1"
}

@test "mdoctor check degrades to skips when probe binaries are missing" {
  local rc=0
  PATH="$TEST_TMP/farm" HOME="$TEST_TMP/home" _run_lim ./mdoctor check >"$TEST_TMP/check.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { tail -n 20 "$TEST_TMP/check.out"; fail "Expected mdoctor check exit 0 with missing probe binaries, got $rc"; }
  for _skip in \
    "Skipping connectivity probe: ping not found." \
    "Skipping DNS timing probe: nslookup not found." \
    "Skipping top-CPU probe: ps not found." \
    "Skipping top-memory probe: ps not found." \
    "Skipping zombie probe: ps not found."; do
    assert_contains "$TEST_TMP/check.out" "$_skip"
  done
  # ss-based probes only exist on the Linux branches (macOS uses
  # lsof/netstat): the listening-ports skip applies on Linux only.
  if [ "$(uname -s)" = "Linux" ]; then
    assert_contains "$TEST_TMP/check.out" "Skipping listening-ports probe: ss not found."
  fi
}

@test "mdoctor diagnose degrades to skips when probe binaries are missing" {
  local rc=0
  PATH="$TEST_TMP/farm" HOME="$TEST_TMP/home" _run_lim ./mdoctor diagnose >"$TEST_TMP/diag.out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { tail -n 20 "$TEST_TMP/diag.out"; fail "Expected mdoctor diagnose exit 0 with missing probe binaries, got $rc"; }
  for _skip in \
    "Skipping top-CPU probe: ps not found." \
    "Skipping zombie probe: ps not found."; do
    assert_contains "$TEST_TMP/diag.out" "$_skip"
  done
  # The ss connection probe is Linux-only (macOS uses netstat).
  if [ "$(uname -s)" = "Linux" ]; then
    assert_contains "$TEST_TMP/diag.out" "Skipping connection-count probe: ss not found."
  fi
}
