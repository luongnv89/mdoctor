#!/usr/bin/env bats
#
# Regression tests for issue #99 (Task 11.5):
#   cheapen log() and the per-file cost of safe_remove.
# - log() must produce the same "[YYYY-MM-DD HH:MM:SS] msg" line on
#   stdout and in LOGFILE — without forking `date`/`tee` per call
#   (Bash 3.2 has no printf '%(...)T', so the fork-free timestamp is
#   seeded once and derived via SECONDS + civil-from-days arithmetic).
# - _normalize_path/_canonical_path OUTVAR forms match their echo forms.
# - oplog_ensure_file work (dirname/mkdir) runs once per OPLOGFILE, not
#   on op_record's per-action path.
# - safe_find_delete dry-run semantics unchanged: every candidate logged
#   and op_recorded, nothing deleted.
# - 200 log() calls stay far below the legacy 177 ms baseline (loose
#   100 ms ceiling — the point is the 25x mechanism, not a flaky micro).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/safety.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT TMPHOME
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-logperf.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  mkdir -p "$TMPHOME/.config/mdoctor" "$TMPHOME/.cache/perf"
  export HOME="$TMPHOME"
  export LOGFILE="$TMPHOME/mdoctor.log"
  export OPLOGFILE="$TMPHOME/.config/mdoctor/operations.log"
  export MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPHOME/.config/mdoctor/cleanup_whitelist"
  local i=0
  while [ "$i" -lt 20 ]; do
    : > "$TMPHOME/.cache/perf/f$i"
    i=$((i + 1))
  done
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "log() writes the bracketed timestamp line to stdout and LOGFILE" {
  local out
  out="$(log "hello world")"
  case "$out" in
    \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]\ hello\ world) ;;
    *) fail "bad log line: $out" ;;
  esac
  assert_contains "$LOGFILE" "] hello world"
}

@test "timestamp() agrees with the system clock (same-second sandwich)" {
  local before after ts
  before="$(date '+%Y-%m-%d %H:%M:%S')"
  ts="$(timestamp)"
  after="$(date '+%Y-%m-%d %H:%M:%S')"
  { [ "$ts" = "$before" ] || [ "$ts" = "$after" ]; } \
    || fail "timestamp '$ts' outside [$before .. $after]"
}

@test "log() needs no date/tee fork per call once seeded" {
  timestamp >/dev/null # seed this process before stubbing
  date() { return 99; }
  tee() { return 99; }
  log "fork free line" >/dev/null || fail "log failed with stubbed date/tee"
  assert_contains "$LOGFILE" "] fork free line"
}

@test "oplog ensure work runs once per OPLOGFILE, not per action" {
  op_session_start "perf-test"
  local count_file="$TMPHOME/dirname.count"
  dirname() { echo x >>"$count_file"; command dirname "$@"; }
  mkdir() { return 99; }
  date() { return 99; }
  op_record "A" "t1"
  op_record "B" "t2"
  op_error "E" "t3"
  op_session_end "ok"
  [ ! -f "$count_file" ] || fail "dirname ran on the per-action oplog path"
  # Note: assert_contains needles are grep regexes — avoid '[' ']'.
  assert_contains "$OPLOGFILE" "ACTION"
  assert_contains "$OPLOGFILE" "ERROR"
  assert_contains "$OPLOGFILE" "session end"
}

@test "_normalize_path OUTVAR form matches the echo form" {
  local c v e
  for c in "/a//b" "/a/./b/" "/a/b/." "/" "////" "/a//./b//." "/a/" "" "/var/crash//x/"; do
    _normalize_path "$c" v
    e="$(_normalize_path "$c")"
    [ "$v" = "$e" ] || fail "normalize mismatch for '$c': var='$v' echo='$e'"
  done
}

@test "_canonical_path resolves links identically to realpath" {
  ln -s "$TMPHOME/.cache/perf/f1" "$TMPHOME/.cache/perf/link1"
  local got="" plain="" want_link want_plain
  _canonical_path "$TMPHOME/.cache/perf/link1" got
  _canonical_path "$TMPHOME/.cache/perf/f1" plain
  want_link="$(realpath "$TMPHOME/.cache/perf/link1" 2>/dev/null || readlink -f "$TMPHOME/.cache/perf/link1")"
  want_plain="$(realpath "$TMPHOME/.cache/perf/f1" 2>/dev/null || readlink -f "$TMPHOME/.cache/perf/f1")"
  [ -n "$got" ] || fail "empty canonical path for symlink"
  [ "$got" = "$want_link" ] || fail "canonical mismatch: '$got' vs '$want_link'"
  [ "$plain" = "$want_plain" ] || fail "link-free canonical mismatch: '$plain' vs '$want_plain'"
}

@test "safe_find_delete dry-run logs and records every candidate, deletes nothing" {
  export DRY_RUN=true
  safe_find_delete "$TMPHOME/.cache/perf" -type f >/dev/null || fail "safe_find_delete rc=$?"
  local remaining
  remaining="$(find "$TMPHOME/.cache/perf" -type f | wc -l | tr -d ' ')"
  [ "$remaining" = "20" ] || fail "dry-run deleted files ($remaining left)"
  assert_contains "$LOGFILE" "DRY RUN"
  assert_contains "$OPLOGFILE" "DRY_RUN_REMOVE"
}

@test "safe_remove dry-run validates, logs and records with stubbed coreutils" {
  export DRY_RUN=true
  timestamp >/dev/null
  op_session_start "stubbed" # performs the one-time oplog ensure
  date() { return 99; }
  tee() { return 99; }
  dirname() { return 99; }
  mkdir() { return 99; }
  safe_remove "$TMPHOME/.cache/perf/f0" >/dev/null \
    || fail "safe_remove rc=$? with stubbed date/tee/dirname/mkdir"
  [ -f "$TMPHOME/.cache/perf/f0" ] || fail "dry-run removed f0"
  assert_contains "$LOGFILE" "DRY RUN"
  assert_contains "$OPLOGFILE" "DRY_RUN_REMOVE"
}

@test "200 log() calls stay far below the 177ms legacy baseline" {
  # Timed in a plain bash -c child: the bats DEBUG trap would bill its
  # own per-statement overhead onto the measurement.
  local elapsed_ms
  elapsed_ms="$(
    LOGFILE="$LOGFILE" REPO="$ROOT_DIR" bash -c '
      source "$REPO/lib/logging.sh"
      s="$(perl -MTime::HiRes=time -e "printf \"%.3f\", time()" 2>/dev/null || echo "")"
      i=0
      while [ "$i" -lt 200 ]; do
        log "bench $i" >/dev/null
        i=$((i + 1))
      done
      e="$(perl -MTime::HiRes=time -e "printf \"%.3f\", time()" 2>/dev/null || echo "")"
      [ -n "$s" ] && [ -n "$e" ] || exit 42
      awk -v s="$s" -v e="$e" "BEGIN {printf \"%d\", (e - s) * 1000}"
    '
  )" || { [ "$?" -eq 42 ] && skip "no high-res timer available"; fail "timed run failed"; }
  # Legacy echo|tee -a cost 177ms+ on the reporter host (~470ms on the
  # slow CI box here). 100ms is a 5x margin over the measured ~5-20ms
  # new path and still fails for the old pipeline.
  [ "$elapsed_ms" -lt 100 ] || fail "log() x200 took ${elapsed_ms}ms"
}
