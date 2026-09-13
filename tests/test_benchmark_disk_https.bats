#!/usr/bin/env bats
#
# test_benchmark_disk_https.bats
# Issue #103 (Task 11.9): real-disk + HTTPS benchmark.
#   * the disk test file is staged in a safety.sh-validated
#     `mdoctor-bench.*` scratch dir under the per-user cache dir — never
#     ${TMPDIR:-/tmp}, which is tmpfs (RAM) on systemd Linux;
#   * a RAM-backed (tmpfs/ramfs) target refuses to report numbers;
#   * dd flushes via conv=fdatasync and the read pass uses iflag=direct
#     where supported — the bare system-wide `sync` is gone;
#   * both network probes share MDOCTOR_BENCH_HOST (default example.com)
#     and the fetch runs over HTTPS — no "http://" literal remains.
# Every external command (df/mount/dd/nslookup/curl) is a recording stub:
# nothing here writes the real 256MB payload or reaches the network.
# Bash 3.2 compatible.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-benchdisk.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  export TMPHOME
  mkdir -p "$TMPHOME/.config/mdoctor"
  printf '# empty\n' > "$TMPHOME/.config/mdoctor/cleanup_whitelist"

  STUBBIN="$TMPHOME/stubbin"
  export STUBBIN
  mkdir -p "$STUBBIN"

  # df — GNU `df -T` output; the Type column answers from $STUB_FSTYPE.
  cat >"$STUBBIN/df" <<'EOF'
#!/usr/bin/env bash
echo "Filesystem Type 1K-blocks Used Available Use% Mounted on"
echo "stubfs ${STUB_FSTYPE:-ext4} 1024000 1 1023999 1% ${STUB_MOUNT:-/}"
exit 0
EOF

  # mount — "dev on /mp (type, opts)" lines for the macOS ancestor walk.
  cat >"$STUBBIN/mount" <<'EOF'
#!/usr/bin/env bash
echo "stubdev on ${STUB_MOUNT:-/} (${STUB_FSTYPE:-ext4}, local)"
exit 0
EOF

  # dd — records argv; creates a tiny of= target like a real truncating
  # write, never the real payload. STUB_DD_NOCONV/STUB_DD_NOIFLAG make
  # the stub reject conv=*/iflag=* argv like a dd lacking the feature.
  cat >"$STUBBIN/dd" <<'EOF'
#!/usr/bin/env bash
if [ -n "${MDOCTOR_STUB_LOG:-}" ]; then
  printf 'dd %s\n' "$*" >>"$MDOCTOR_STUB_LOG"
fi
if [ -n "${STUB_DD_NOCONV:-}" ]; then
  case "$*" in *conv=*) exit 1 ;; esac
fi
if [ -n "${STUB_DD_NOIFLAG:-}" ]; then
  case "$*" in *iflag=*) exit 1 ;; esac
fi
_out=""
for _a in "$@"; do
  case "$_a" in of=*) _out="${_a#of=}" ;; esac
done
case "$_out" in
  ""|/dev/*) ;;
  *) : >"$_out" 2>/dev/null || true ;;
esac
exit 0
EOF

  # nslookup / curl — record argv, succeed instantly, no network.
  cat >"$STUBBIN/nslookup" <<'EOF'
#!/usr/bin/env bash
if [ -n "${MDOCTOR_STUB_LOG:-}" ]; then
  printf 'nslookup %s\n' "$*" >>"$MDOCTOR_STUB_LOG"
fi
exit 0
EOF
  cat >"$STUBBIN/curl" <<'EOF'
#!/usr/bin/env bash
if [ -n "${MDOCTOR_STUB_LOG:-}" ]; then
  printf 'curl %s\n' "$*" >>"$MDOCTOR_STUB_LOG"
fi
exit 0
EOF

  # purge — the macOS cache-drop; STUB_PURGE_RC controls its exit.
  cat >"$STUBBIN/purge" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_PURGE_RC:-0}"
EOF
  chmod +x "$STUBBIN/df" "$STUBBIN/mount" "$STUBBIN/dd" "$STUBBIN/nslookup" "$STUBBIN/curl" "$STUBBIN/purge"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

# _bench_run FSTYPE MOUNT [EXTRA_ENV...] — run run_benchmark hermetic.
_bench_run() {
  local _fstype="$1" _mount="$2" _out="$3" _log="$4"
  shift 4
  : >"$_log"
  env STUB_FSTYPE="$_fstype" STUB_MOUNT="$_mount" \
    MDOCTOR_STUB_LOG="$_log" HOME="$TMPHOME" \
    PATH="$STUBBIN:$PATH" "$@" \
    bash -c '
      source lib/platform.sh
      source lib/common.sh
      source lib/benchmark.sh
      run_benchmark
    ' >"$_out" 2>&1
}

@test "benchmark lib contains no cleartext URL" {
  # Acceptance literal: grep -c 'http://' lib/benchmark.sh must be 0.
  [ "$(grep -c 'http://' "$ROOT_DIR/lib/benchmark.sh")" -eq 0 ]
}

@test "benchmark uses fdatasync flush, direct read, no bare sync, no hardcoded host" {
  grep -q 'conv=fdatasync' "$ROOT_DIR/lib/benchmark.sh" || fail "conv=fdatasync missing"
  grep -q 'iflag=direct' "$ROOT_DIR/lib/benchmark.sh" || fail "iflag=direct missing"
  if grep -nE '^[[:space:]]*sync([[:space:]]*)$' "$ROOT_DIR/lib/benchmark.sh"; then
    fail "bare system-wide sync remains in lib/benchmark.sh"
  fi
  if grep -q 'google\.com' "$ROOT_DIR/lib/benchmark.sh"; then
    fail "hardcoded third-party host remains in lib/benchmark.sh"
  fi
  grep -q 'MDOCTOR_BENCH_HOST' "$ROOT_DIR/lib/benchmark.sh" || fail "MDOCTOR_BENCH_HOST not wired"
}

@test "disk benchmark refuses to report when the scratch filesystem is tmpfs" {
  _bench_run tmpfs "$TMPHOME" "$TMPHOME/t3.out" "$TMPHOME/t3.log"
  assert_contains "$TMPHOME/t3.out" "tmpfs"
  assert_contains "$TMPHOME/t3.out" "skipped"
  # no fabricated numbers: no MB/s row may be printed
  if grep -q 'MB/s' "$TMPHOME/t3.out"; then
    fail "disk MB/s numbers were reported on a tmpfs target: $(cat "$TMPHOME/t3.out")"
  fi
  # refusal precedes the write: the payload file never reached dd
  if grep -q 'of=.*bench_disk' "$TMPHOME/t3.log"; then
    fail "dd wrote the payload file despite the tmpfs refusal"
  fi
}

@test "disk benchmark stages under the per-user cache dir and cleans up" {
  _bench_run ext4 / "$TMPHOME/t4.out" "$TMPHOME/t4.log"
  assert_contains "$TMPHOME/t4.out" "MB/s"
  local _of
  _of="$(grep -o 'of=[^ ]*bench_disk' "$TMPHOME/t4.log" | head -1)"
  _of="${_of#of=}"
  # platform_cache_dir: ~/Library/Caches on macOS, ~/.cache on Linux —
  # resolve through the real helper so the assertion tracks the code.
  local _cachebase
  _cachebase="$(HOME="$TMPHOME" bash -c 'source lib/platform.sh; platform_cache_dir')"
  case "$_of" in
    "$_cachebase"/mdoctor/mdoctor-bench.*/*) ;;
    *) fail "expected bench_disk under platform_cache_dir()/mdoctor/mdoctor-bench.*, got: $_of" ;;
  esac
  case "$_of" in
    /tmp/*|/var/tmp/*|"${TMPDIR:-/tmp}"/*) fail "benchmark file staged under a tmpfs-prone temp root: $_of" ;;
  esac
  # write flushed via conv=fdatasync; read bypassed cache via iflag=direct
  grep -q 'of=[^ ]*bench_disk .*conv=fdatasync' "$TMPHOME/t4.log" ||
    fail "write pass ran without conv=fdatasync: $(cat "$TMPHOME/t4.log")"
  grep -q 'if=.*bench_disk.*iflag=direct' "$TMPHOME/t4.log" ||
    fail "read pass ran without iflag=direct: $(cat "$TMPHOME/t4.log")"
  # scratch dir removed on the normal exit path
  local _left
  _left="$(find "$_cachebase/mdoctor" -name 'mdoctor-bench.*' 2>/dev/null)"
  [ -z "$_left" ] || fail "scratch dir not cleaned after run: $_left"
}

@test "MDOCTOR_BENCH_DIR override stages the test file there" {
  mkdir -p "$TMPHOME/custom-bench"
  _bench_run ext4 / "$TMPHOME/t5.out" "$TMPHOME/t5.log" MDOCTOR_BENCH_DIR="$TMPHOME/custom-bench"
  local _of
  _of="$(grep -o 'of=[^ ]*bench_disk' "$TMPHOME/t5.log" | head -1)"
  _of="${_of#of=}"
  case "$_of" in
    "$TMPHOME"/custom-bench/mdoctor-bench.*/*) ;;
    *) fail "expected bench_disk under MDOCTOR_BENCH_DIR, got: $_of" ;;
  esac
  local _left
  _left="$(find "$TMPHOME/custom-bench" -name 'mdoctor-bench.*' 2>/dev/null)"
  [ -z "$_left" ] || fail "scratch dir not cleaned after run: $_left"
}

@test "network probes use MDOCTOR_BENCH_HOST default example.com over HTTPS" {
  _bench_run ext4 / "$TMPHOME/t6.out" "$TMPHOME/t6.log"
  grep -q 'nslookup example\.com' "$TMPHOME/t6.log" ||
    fail "nslookup did not resolve the default host: $(cat "$TMPHOME/t6.log")"
  grep -q 'curl .*https://example\.com' "$TMPHOME/t6.log" ||
    fail "curl did not fetch https://example.com: $(cat "$TMPHOME/t6.log")"
  if grep -q 'curl .*http://' "$TMPHOME/t6.log"; then
    fail "curl fetched a cleartext URL"
  fi
}

@test "MDOCTOR_BENCH_HOST override feeds both DNS and HTTPS probes" {
  _bench_run ext4 / "$TMPHOME/t7.out" "$TMPHOME/t7.log" MDOCTOR_BENCH_HOST="bench.internal"
  grep -q 'nslookup bench\.internal' "$TMPHOME/t7.log" ||
    fail "nslookup did not resolve the override host: $(cat "$TMPHOME/t7.log")"
  grep -q 'curl .*https://bench\.internal' "$TMPHOME/t7.log" ||
    fail "curl did not fetch the override host over HTTPS: $(cat "$TMPHOME/t7.log")"
}

@test "disk benchmark refuses to report when dd cannot flush to media" {
  # A dd with no conv=fdatasync/fsync/osync cannot commit the payload:
  # the write number would be a page-cache write. Fail closed.
  _bench_run ext4 / "$TMPHOME/t8.out" "$TMPHOME/t8.log" STUB_DD_NOCONV=1
  assert_contains "$TMPHOME/t8.out" "skipped"
  if grep -q 'MB/s' "$TMPHOME/t8.out"; then
    fail "disk MB/s numbers reported although dd cannot sync to media: $(cat "$TMPHOME/t8.out")"
  fi
  if grep -q 'of=.*bench_disk' "$TMPHOME/t8.log"; then
    fail "dd wrote the payload file despite the no-flush refusal"
  fi
}

@test "disk read is skipped when the page cache cannot be bypassed" {
  # No iflag=direct and (on macOS) a failing purge => a plain read would
  # be a page-cache hit on the just-written file. Write still reports.
  _bench_run ext4 / "$TMPHOME/t9.out" "$TMPHOME/t9.log" STUB_DD_NOIFLAG=1 STUB_PURGE_RC=1
  grep -q 'of=[^ ]*bench_disk .*conv=fdatasync' "$TMPHOME/t9.log" ||
    fail "write pass did not run with conv=fdatasync: $(cat "$TMPHOME/t9.log")"
  # Only the iflag=direct probe may read bench_disk — never a plain
  # (cache-hit) read.
  if grep 'if=[^ ]*bench_disk of=/dev/null' "$TMPHOME/t9.log" | grep -vq 'iflag=direct'; then
    fail "a cached read ran despite no cache bypass: $(cat "$TMPHOME/t9.log")"
  fi
  assert_contains "$TMPHOME/t9.out" "skipped"
  # no read number may be printed (a page-cache hit is not disk I/O)
  if grep -qE 'Read \(256 MB\):.*MB/s' "$TMPHOME/t9.out"; then
    fail "read number reported without a cache bypass: $(cat "$TMPHOME/t9.out")"
  fi
  grep -q 'Disk Read.*skipped' "$TMPHOME/t9.out" ||
    fail "read row did not render skipped: $(cat "$TMPHOME/t9.out")"
}
