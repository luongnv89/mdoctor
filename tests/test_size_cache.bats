#!/usr/bin/env bats
#
# Regression test for Task 11.2 / issue #96 (F-PERF-005):
#   the force-mode pre-flight and the cleanup modules share one keyed,
#   per-process size cache (lib/preflight.sh), so every path is measured
#   at most once — the cache increments MDOCTOR_SIZE_CACHE_MEASUREMENTS
#   on each real probe — and a path nested inside an already-measured
#   parent is excluded from the estimate. On macOS the same mechanism
#   makes DerivedData a single walk instead of three.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init
source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/disk.sh"
source "$ROOT_DIR/lib/preflight.sh"
source "$ROOT_DIR/lib/safety.sh"

setup() {
  # The cache is per-process and bats runs every @test in one process —
  # reset between tests (same convention as _MDOCTOR_FIND_PRINTF_OK).
  size_cache_reset
}

@test "size_cache_kb measures each path at most once per process" {
  local dir="$BATS_TEST_TMPDIR/cache-unit"
  mkdir -p "$dir/sub"
  head -c 4096 /dev/zero >"$dir/sub/blob.bin" 2>/dev/null \
    || dd if=/dev/zero of="$dir/sub/blob.bin" bs=1024 count=4 2>/dev/null

  size_cache_kb "$dir"
  local first="$MDOCTOR_SIZE_KB"
  size_cache_kb "$dir/"   # trailing-slash spelling hits the same key
  size_cache_kb "$dir"
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 1 ]
  [ -n "$first" ]
  [ "$(size_cache_lookup "$dir")" = "$first" ]
  # The cached figure is a real du -sk total for the tree.
  local real
  real=$(du -sk "$dir" | awk 'NR==1{print $1+0}')
  [ "$first" = "$real" ]
}

@test "a path nested inside a measured parent is excluded from the estimate" {
  local parent="$BATS_TEST_TMPDIR/nest-parent"
  mkdir -p "$parent/child"
  head -c 4096 /dev/zero >"$parent/a.bin" 2>/dev/null \
    || dd if=/dev/zero of="$parent/a.bin" bs=1024 count=4 2>/dev/null
  head -c 2048 /dev/zero >"$parent/child/b.bin" 2>/dev/null \
    || dd if=/dev/zero of="$parent/child/b.bin" bs=1024 count=2 2>/dev/null

  preflight_size_path "$parent"
  local parent_kb="$MDOCTOR_SIZE_KB" parent_add="$MDOCTOR_SIZE_ADD"
  [ -n "$parent_kb" ]
  [ "$parent_add" = "$parent_kb" ]

  # Fixture total = parent, not parent + child: the child is covered by
  # the measured parent, so it is neither measured nor added.
  preflight_size_path "$parent/child"
  [ "$MDOCTOR_SIZE_COVER" = "$parent" ]
  [ "$MDOCTOR_SIZE_ADD" -eq 0 ]
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 1 ]

  # A re-query of the parent displays the cached size but adds 0 again.
  preflight_size_path "$parent"
  [ "$MDOCTOR_SIZE_KB" = "$parent_kb" ]
  [ "$MDOCTOR_SIZE_ADD" -eq 0 ]
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 1 ]
}

@test "failed probes are never cached and do not bump the counter" {
  local rc=0
  size_cache_kb "$BATS_TEST_TMPDIR/does-not-exist" || rc=$?
  [ "$rc" -eq "$MDOCTOR_SIZE_ERR_NO_TARGET" ]
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 0 ]
  # Retry after creating the target measures it (a miss was not stored).
  mkdir -p "$BATS_TEST_TMPDIR/does-not-exist"
  size_cache_kb "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 1 ]
}

@test "a pre-flight measurement serves both DerivedData module reads (issue #96)" {
  # macOS walks DerivedData three times without the cache: pre-flight,
  # clean_xcode and dev_caches' _clean_cache. In-process equivalent of the
  # three readers against one path — only the first may measure.
  local dd="$BATS_TEST_TMPDIR/DerivedData"
  mkdir -p "$dd/Module-a"
  head -c 2048 /dev/zero >"$dd/Module-a/f.bin" 2>/dev/null \
    || dd if=/dev/zero of="$dd/Module-a/f.bin" bs=1024 count=2 2>/dev/null

  preflight_size_path "$dd"   # cleanup.sh force pre-flight
  size_cache_kb "$dd"         # clean_xcode's read
  size_cache_kb "$dd"         # dev_caches _clean_cache's read
  [ "$MDOCTOR_SIZE_CACHE_MEASUREMENTS" -eq 1 ]
}

@test "DerivedData and CoreSimulator sizing sites route through the cache" {
  # xcode.sh must not du-walk either tree directly anymore.
  ! grep -n 'du_size_kb' "$ROOT_DIR/cleanups/xcode.sh" \
    || fail "cleanups/xcode.sh still measures a path directly"
  # dev_caches keeps one direct probe for the dynamic node_modules scan,
  # but the fixed cache roots must go through the cache.
  ! grep -n 'du_size_kb "$cache_dir"' "$ROOT_DIR/cleanups/dev_caches.sh" \
    || fail "cleanups/dev_caches.sh _clean_cache still measures directly"
}

@test "force pre-flight plus clean measures each distinct root once (e2e)" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  local stubbin="$BATS_TEST_TMPDIR/stubbin"
  local calls="$BATS_TEST_TMPDIR/du.calls"
  local out="$BATS_TEST_TMPDIR/out.log"

  # The pre-flight root list is platform-shaped (lib/platform.sh): trash
  # and cache roots differ between macOS and Linux, and the macOS block
  # adds DerivedData + CoreSimulator. Build the fixture and expectations
  # from the same platform predicates cleanup.sh uses so the
  # every-root-once assertion checks the roots this platform lists.
  local -a roots=()
  local nested="" nested_parent=""
  if is_macos; then
    roots=(
      "$fake_home/.Trash"
      "$fake_home/Library/Caches"
      "$fake_home/.npm"
      "$fake_home/.cache/pip"
      "$fake_home/.m2/repository"
      "$fake_home/.gradle/caches"
      "$fake_home/go/pkg/mod/cache"
      "$fake_home/.cargo/registry/cache"
      "$fake_home/Library/Developer/Xcode/DerivedData"
      "$fake_home/Library/Developer/CoreSimulator/Caches"
    )
  else
    roots=(
      "$fake_home/.local/share/Trash/files"
      "$fake_home/.cache"
      "$fake_home/.npm"
      "$fake_home/.cache/pip"
      "$fake_home/.m2/repository"
      "$fake_home/.gradle/caches"
      "$fake_home/go/pkg/mod/cache"
      "$fake_home/.cargo/registry/cache"
    )
    # Only the Linux list carries a nested pair: ~/.cache/pip under the
    # measured ~/.cache root.
    nested="$fake_home/.cache/pip"
    nested_parent="$fake_home/.cache"
  fi
  mkdir -p "${roots[@]}" "$stubbin"
  local d
  for d in "${roots[@]}"; do
    head -c 2048 /dev/zero >"$d/blob.bin" 2>/dev/null \
      || dd if=/dev/zero of="$d/blob.bin" bs=1024 count=2 2>/dev/null
  done

  # du stub: record the last argv (the du -sk target), then exec the real
  # binary so sizes stay genuine. PATH stubs from tests/helpers/bin keep
  # docker/apt-get/sudo hermetic even under a bare `bats` invocation.
  local real_du
  real_du="$(command -v du)"
  printf '#!/usr/bin/env bash\nlast=""; for a in "$@"; do last="$a"; done\nprintf "%%s\\n" "$last" >> "%s"\nexec "%s" "$@"\n' \
    "$calls" "$real_du" >"$stubbin/du"
  chmod +x "$stubbin/du"

  HOME="$fake_home" MDOCTOR_ASSUME_YES=true \
    PATH="$ROOT_DIR/tests/helpers/bin:$stubbin:$PATH" \
    "$ROOT_DIR/cleanup.sh" --force >"$out" 2>&1 || true

  assert_contains "$out" "Estimated reclaim size:"
  if [ -n "$nested" ]; then
    # The nested fixture is announced as covered by its measured parent.
    assert_contains "$out" "included in ${nested_parent}"
  fi

  # No du -sk target ran twice across the whole force run.
  [ -f "$calls" ] || fail "du stub saw no calls — pre-flight never measured"
  local dupes
  dupes=$(sort "$calls" | uniq -d)
  [ -z "$dupes" ] || fail "du ran more than once on: $dupes"

  if [ -n "$nested" ]; then
    # The nested root was never walked standalone (covered by its parent,
    # then deleted by the caches module before dev_caches could ask).
    if grep -Fxq "$nested" "$calls"; then
      fail "nested ${nested} was du-walked as its own root"
    fi
  fi

  # Every remaining listed root was measured exactly once.
  local p
  for p in "${roots[@]}"; do
    if [ -n "$nested" ] && [ "$p" = "$nested" ]; then
      continue
    fi
    [ "$(grep -Fxc "$p" "$calls")" -eq 1 ] || fail "expected exactly one du of $p"
  done
}
