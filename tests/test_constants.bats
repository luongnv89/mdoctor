#!/usr/bin/env bats
#
# Regression test for Task 8.7 (#81):
#   lib/constants.sh is the single definition site for size/threshold/
#   timeout values; safety renderers switch on named error constants; the
#   benchmark size derives from its block count; diagnose thresholds are
#   named and env-overridable.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

@test "the KB-per-GB literal is defined exactly once" {
  # BusyBox-grep compatible (no grep --include).
  total=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" | xargs grep -h '1048576' 2>/dev/null | wc -l | tr -d ' ')
  [ "$total" -eq 1 ]
  files=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" | xargs grep -l '1048576' 2>/dev/null)
  [ "$files" = "$ROOT_DIR/lib/constants.sh" ]
}

@test "derived constants resolve to the documented values" {
  source "$ROOT_DIR/lib/constants.sh"
  [ "$MDOCTOR_KB_PER_GB" -eq 1048576 ]
  [ "$MDOCTOR_KB_PER_MB" -eq 1024 ]
  [ "$MDOCTOR_KB_10GB" -eq 10485760 ]
  [ "$MDOCTOR_REPORT_MIN_KB" -eq 102400 ]
  [ "$MDOCTOR_REPORT_WARN_KB" -eq 1048576 ]
  [ "$MDOCTOR_DU_TIMEOUT_S" -eq 30 ]
  [ "$MDOCTOR_BENCH_DISK_MB" -eq 256 ]
}

@test "diagnose thresholds honor environment overrides" {
  out=$(MDOCTOR_DIAG_CPU_HIGH=90 MDOCTOR_DIAG_MEM_CRIT=99 bash -c 'source "$0/lib/constants.sh"; printf "%s/%s" "$MDOCTOR_DIAG_CPU_HIGH" "$MDOCTOR_DIAG_MEM_CRIT"' "$ROOT_DIR")
  [ "$out" = "90/99" ]
  source "$ROOT_DIR/lib/constants.sh"
  [ "$MDOCTOR_DIAG_CPU_HIGH" -eq 80 ]
  [ "$MDOCTOR_DIAG_CONN_HIGH" -eq 5000 ]
}

@test "safety renderers switch on named error constants" {
  named=$(grep -c '"$MDOCTOR_SAFE_ERR_' "$ROOT_DIR/lib/safety.sh")
  [ "$named" -ge 12 ]
  bare=$(grep -E '^\s+[0-9]+\)' "$ROOT_DIR/lib/safety.sh" | wc -l | tr -d ' ')
  [ "$bare" -eq 0 ]
}

@test "benchmark size derives from its block count" {
  grep -q 'count="$MDOCTOR_BENCH_DISK_MB"' "$ROOT_DIR/lib/benchmark.sh"
  grep -q 'awk -v sz="$count"' "$ROOT_DIR/lib/benchmark.sh"
  bare=$(grep -c 'sz=256' "$ROOT_DIR/lib/benchmark.sh" || true)
  [ "$bare" -eq 0 ]
}

@test "diagnose keeps no tunable numeric threshold inline" {
  leftover=$(grep -E '\(\( .* (>|<) [1-9][0-9]+' "$ROOT_DIR/checks/diagnose_performance.sh" | grep -v 'MDOCTOR_' || true)
  [ -z "$leftover" ]
}
