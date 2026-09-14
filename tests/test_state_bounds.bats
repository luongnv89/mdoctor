#!/usr/bin/env bats
# Issue #113 (Task 12.10): persistent state is bounded and collision-free,
# best-effort state writes never abort a run, and every shared lib sources
# cleanly under both errexit postures.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME STUBBIN
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-bounds.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  # `date` stub: forces every history filename timestamp to the same
  # second so the same-second collision case is deterministic.
  STUBBIN="$TMPHOME/stubbin"
  mkdir -p "$STUBBIN"
  cat > "$STUBBIN/date" <<'STUB'
#!/usr/bin/env bash
case " $*" in
  *%Y%m%d_%H%M%S*) printf '20260101_000000\n' ;;
  *%Y-%m-%dT%H:%M:%SZ*) printf '2026-01-01T00:00:00Z\n' ;;
  *) exec /bin/date "$@" ;;
esac
STUB
  chmod +x "$STUBBIN/date"
}

teardown_file() {
  chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
  rm -rf "$TMPHOME"
}

@test "two history saves in the same second produce two entries" {
  rm -rf "$TMPHOME/.mdoctor"
  # Two real processes (distinct PIDs) saving in the same stubbed second —
  # `$$` inside `( )` subshells is the parent's PID, so `bash -c` is used
  # to get the same isolation two `mdoctor check` runs have.
  local i
  for i in 1 2; do
    PATH="$STUBBIN:$PATH" HOME="$TMPHOME" \
      bash -c 'source "$1/lib/history.sh" && history_save 90 "good" 0 0' _ "$ROOT_DIR" \
      || fail "history_save run $i failed"
  done
  local count
  count="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 2 ] || fail "expected 2 distinct entries for the same second, got $count"
  # Same-process saves must not collide either (sequence suffix).
  PATH="$STUBBIN:$PATH" HOME="$TMPHOME" \
    bash -c 'source "$1/lib/history.sh" && history_save 91 "good" 0 0 && history_save 92 "good" 0 0' _ "$ROOT_DIR" \
    || fail "same-process history_save failed"
  count="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 4 ] || fail "expected 4 entries after two more same-second saves, got $count"
}

@test "history directory is pruned to MDOCTOR_HISTORY_KEEP" {
  rm -rf "$TMPHOME/.mdoctor"
  mkdir -p "$TMPHOME/.mdoctor/history"
  local i
  for i in 1 2 3 4 5 6 7; do
    printf '{"timestamp":"2020-01-0%dT00:00:00Z","score":80,"rating":"ok","warnings":0,"failures":0}\n' "$i" \
      > "$TMPHOME/.mdoctor/history/2020010${i}_000000-1-1.json"
  done
  (
    HOME="$TMPHOME"
    MDOCTOR_HISTORY_KEEP=5
    export HOME MDOCTOR_HISTORY_KEEP
    source "$ROOT_DIR/lib/history.sh"
    history_save 88 "ok" 0 0
  ) || fail "history_save failed"
  local count
  count="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 5 ] || fail "expected pruning to 5 entries, got $count"
  # Oldest entries are the ones removed; the newest save survives.
  assert_file_not_exists "$TMPHOME/.mdoctor/history/20200101_000000-1-1.json"
  assert_file_not_exists "$TMPHOME/.mdoctor/history/20200102_000000-1-1.json"
  assert_file_exists "$TMPHOME/.mdoctor/history/20200107_000000-1-1.json"
  # Newest file is the just-saved entry (score 88).
  local newest
  newest="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | sort | tail -n 1)"
  grep -q '"score":88' "$newest" || fail "newest history entry is not the fresh save: $newest"
}

@test "history prune honors the cleanup whitelist" {
  rm -rf "$TMPHOME/.mdoctor"
  mkdir -p "$TMPHOME/.mdoctor/history"
  local i
  for i in 1 2 3 4 5; do
    printf '{"timestamp":"2020-01-0%dT00:00:00Z","score":80,"rating":"ok","warnings":0,"failures":0}\n' "$i" \
      > "$TMPHOME/.mdoctor/history/2020010${i}_000000-1-1.json"
  done
  # The whitelist is the user's declared protection list: the two oldest
  # entries must survive pruning and still count toward the cap (review
  # finding on #223 — every other deletion path consults it).
  cat > "$TMPHOME/cleanup_whitelist" <<EOF
$TMPHOME/.mdoctor/history/20200101_000000-1-1.json
$TMPHOME/.mdoctor/history/20200102_000000-1-1.json
EOF
  (
    HOME="$TMPHOME"
    MDOCTOR_HISTORY_KEEP=3
    MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPHOME/cleanup_whitelist"
    export HOME MDOCTOR_HISTORY_KEEP MDOCTOR_CLEANUP_WHITELIST_FILE
    source "$ROOT_DIR/lib/history.sh"
    history_save 88 "ok" 0 0
  ) || fail "history_save failed"
  assert_file_exists "$TMPHOME/.mdoctor/history/20200101_000000-1-1.json"
  assert_file_exists "$TMPHOME/.mdoctor/history/20200102_000000-1-1.json"
  # Bound still holds at keep=3: the two protected entries plus the
  # just-saved one; the three unprotected oldest were removed.
  assert_file_not_exists "$TMPHOME/.mdoctor/history/20200103_000000-1-1.json"
  assert_file_not_exists "$TMPHOME/.mdoctor/history/20200105_000000-1-1.json"
  local count
  count="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 3 ] || fail "expected 3 entries (2 protected + fresh), got $count"
}

@test "leading-zero caps are parsed as decimal, not octal" {
  rm -rf "$TMPHOME/.mdoctor"
  mkdir -p "$TMPHOME/.mdoctor/history"
  local i
  for i in $(seq 1 12); do
    printf '{"timestamp":"2020-01-%02dT00:00:00Z","score":80,"rating":"ok","warnings":0,"failures":0}\n' "$i" \
      > "$TMPHOME/.mdoctor/history/202001$(printf '%02d' "$i")_000000-1-1.json"
  done
  (
    HOME="$TMPHOME"
    MDOCTOR_HISTORY_KEEP=010
    export HOME MDOCTOR_HISTORY_KEEP
    source "$ROOT_DIR/lib/history.sh"
    history_save 88 "ok" 0 0
  ) || fail "history_save failed on leading-zero cap"
  local count
  count="$(find "$TMPHOME/.mdoctor/history" -name '*.json' -type f | wc -l | tr -d ' ')"
  [ "$count" -eq 10 ] || fail "expected decimal keep=10 from '010', got $count"
}

@test "operations log rotates by size at MDOCTOR_OPLOG_MAX_BYTES" {
  rm -rf "$TMPHOME/.config"
  mkdir -p "$TMPHOME/.config/mdoctor"
  local oplog="$TMPHOME/.config/mdoctor/operations.log"
  # 40 lines * ~40 bytes > 256-byte cap.
  local i
  for i in $(seq 1 40); do
    printf '[2026-01-01 00:00:00] [ACTION] line %s padding\n' "$i" >> "$oplog"
  done
  (
    HOME="$TMPHOME"
    MDOCTOR_OPLOG_MAX_BYTES=256
    export HOME MDOCTOR_OPLOG_MAX_BYTES
    source "$ROOT_DIR/lib/logging.sh"
    oplog_write "fresh line after rotation"
  ) || fail "oplog_write failed"
  assert_file_exists "${oplog}.1"
  local size
  size="$(stat -c %s "$oplog" 2>/dev/null || stat -f %z "$oplog")"
  [ "$size" -le 256 ] || fail "rotated operations log still exceeds cap: $size"
  grep -q "fresh line after rotation" "$oplog" || fail "post-rotation write did not land in the fresh log"
}

@test "unwritable config dir disables oplog with a warning under both postures" {
  rm -rf "$TMPHOME/rohome"
  mkdir -p "$TMPHOME/rohome"
  chmod 500 "$TMPHOME/rohome"
  # Word-split spec: `set $spec` expands to separate -e/-u/-o args.
  local spec rc
  for spec in "-e -u -o pipefail" "-u -o pipefail"; do
    rc=0
    (
      set $spec
      HOME="$TMPHOME/rohome"
      export HOME
      source "$ROOT_DIR/lib/logging.sh"
      oplog_write "should never land"
      printf 'enabled=%s\n' "$OPLOG_ENABLED"
    ) >"$TMPHOME/rohome.out" 2>"$TMPHOME/rohome.err" || rc=$?
    [ "$rc" -eq 0 ] || fail "oplog_write aborted under 'set $spec' (rc=$rc)"
    assert_contains "$TMPHOME/rohome.out" "enabled=false"
    assert_contains "$TMPHOME/rohome.err" "operations log disabled"
  done
  chmod 700 "$TMPHOME/rohome"
}

@test "unwritable config dir warns on stderr and does not abort the call" {
  rm -rf "$TMPHOME/rohome2"
  mkdir -p "$TMPHOME/rohome2"
  chmod 500 "$TMPHOME/rohome2"
  local rc=0
  (
    set -euo pipefail
    HOME="$TMPHOME/rohome2"
    export HOME
    source "$ROOT_DIR/lib/logging.sh"
    op_session_start "test"
    op_record "A" "t" "d"
    op_session_end "ok"
  ) 2>"$TMPHOME/rohome2.err" || rc=$?
  chmod 700 "$TMPHOME/rohome2"
  [ "$rc" -eq 0 ] || fail "oplog session calls aborted under set -e (rc=$rc)"
  assert_contains "$TMPHOME/rohome2.err" "operations log disabled"
}

@test "mdoctor clean completes with an unwritable HOME (errexit posture)" {
  rm -rf "$TMPHOME/rohome3"
  mkdir -p "$TMPHOME/rohome3/.Trash"
  printf 'stale\n' > "$TMPHOME/rohome3/.Trash/old-file"
  chmod 500 "$TMPHOME/rohome3"
  local rc=0
  HOME="$TMPHOME/rohome3" ./mdoctor clean -m trash \
    >"$TMPHOME/rohome3.out" 2>"$TMPHOME/rohome3.err" || rc=$?
  chmod 700 "$TMPHOME/rohome3"
  [ "$rc" -eq 0 ] || fail "clean aborted on unwritable HOME (rc=$rc): $(cat "$TMPHOME/rohome3.err")"
  assert_contains "$TMPHOME/rohome3.err" "operations log disabled"
  assert_contains "$TMPHOME/rohome3.out" "Cleanup finished"
}

@test "every shared lib sources cleanly under both errexit postures" {
  local f spec rc
  for f in "$ROOT_DIR"/lib/*.sh; do
    # Word-split spec: `set $spec` expands to separate -e/-u/-o args.
    for spec in "-e -u -o pipefail" "-u -o pipefail"; do
      rc=0
      (
        set $spec
        HOME="$TMPHOME"
        export HOME
        source "$f"
      ) 2>"$TMPHOME/source.err" || rc=$?
      [ "$rc" -eq 0 ] || fail "source $f under 'set $spec' failed (rc=$rc): $(cat "$TMPHOME/source.err")"
    done
  done
}

@test "state caps are named constants in lib/constants.sh" {
  grep -q 'export MDOCTOR_HISTORY_KEEP=' "$ROOT_DIR/lib/constants.sh" \
    || fail "MDOCTOR_HISTORY_KEEP not defined in constants.sh"
  grep -q 'export MDOCTOR_OPLOG_MAX_BYTES=' "$ROOT_DIR/lib/constants.sh" \
    || fail "MDOCTOR_OPLOG_MAX_BYTES not defined in constants.sh"
  source "$ROOT_DIR/lib/constants.sh"
  [ "$MDOCTOR_HISTORY_KEEP" -gt 0 ] || fail "MDOCTOR_HISTORY_KEEP not positive"
  [ "$MDOCTOR_OPLOG_MAX_BYTES" -gt 0 ] || fail "MDOCTOR_OPLOG_MAX_BYTES not positive"
}

@test "best-effort state writes succeed under both postures" {
  local spec
  for spec in "-e -u -o pipefail" "-u -o pipefail"; do
    (
      set $spec
      HOME="$TMPHOME"
      export HOME
      source "$ROOT_DIR/lib/history.sh"
      source "$ROOT_DIR/lib/logging.sh"
      history_save 80 "ok" 1 0
      op_session_start "posture-test"
      op_record "A" "t" "d"
      op_session_end "ok"
    ) || fail "state writes failed under 'set $spec'"
  done
}
