#!/usr/bin/env bats
#
# Regression test for Task 8.3 (#77, part 1):
#   the pre-flight estimator lives in lib/preflight.sh, sourced by both
#   entry points; both produce byte-identical estimates for the same target.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

@test "estimator helpers are declared once in lib/preflight.sh" {
  count=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh \) -not -path "$ROOT_DIR/tests/*" | xargs grep -l '^preflight_path_kb()\|^preflight_find_kb()' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  dupes=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh \) -not -path "$ROOT_DIR/tests/*" | xargs grep -l 'md_path_size_kb\|md_find_size_kb\|md_human_kb\|cleanup_preflight_path_kb\|cleanup_preflight_find_kb' 2>/dev/null || true)
  [ -z "$dupes" ]
}

@test "both entry points source the shared preflight module" {
  grep -q 'lib/preflight.sh' "$ROOT_DIR/mdoctor"
  grep -q 'lib/preflight.sh' "$ROOT_DIR/cleanup.sh"
}

@test "mdoctor and direct probe give byte-identical trash estimates" {
  export HOME="$BATS_TEST_TMPDIR/home"
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  trash_dir="$(platform_trash_dir)"
  mkdir -p "$trash_dir" "$HOME/.cache"
  echo hello > "$trash_dir/f.txt"
  expected_kb=$(preflight_path_kb "$trash_dir")
  expected_hr=$(human_readable_kb "$expected_kb")
  out=$(printf 'n\n' | "$ROOT_DIR/mdoctor" clean -m trash --force 2>&1 || true)
  [[ "$out" == *"Trash"*"${trash_dir}"*" (~${expected_hr})"* ]]
  [[ "$out" == *"Estimated reclaim size: ~${expected_hr}"* ]]
}
