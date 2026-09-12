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

@test "pre-flight path carries no per-entry du -sk (Task 11.1)" {
  # Acceptance guard: the two entry points must not spawn `du -sk`.
  dupes=$(grep -l 'du -sk' "$ROOT_DIR/cleanup.sh" "$ROOT_DIR/mdoctor" 2>/dev/null || true)
  [ -z "$dupes" ]
}

@test "preflight_find_kb total matches the retired per-entry du total" {
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  local dir="$BATS_TEST_TMPDIR/size-fixture"
  mkdir -p "$dir/sub/deep"
  printf 'x' > "$dir/a.bin"
  head -c 5000 /dev/zero > "$dir/b.bin" 2>/dev/null || dd if=/dev/zero of="$dir/b.bin" bs=1000 count=5 2>/dev/null
  head -c 12345 /dev/zero > "$dir/sub/c.bin" 2>/dev/null || dd if=/dev/zero of="$dir/sub/c.bin" bs=1000 count=12 2>/dev/null
  printf 'x' > "$dir/sub/deep/d.bin"

  # File matches: expected = sum of the old per-entry `du -sk` figures.
  local expected=0 f sz
  while IFS= read -r -d '' f; do
    sz=$(du -sk "$f" | awk 'NR==1{print $1+0}')
    expected=$((expected + sz))
  done < <(find "$dir" -type f -print0)
  local got
  got=$(preflight_find_kb "$dir" -type f)
  [ "$got" = "$expected" ]

  # Directory matches: a matched dir must still contribute its whole
  # subtree, exactly as `du -sk dir` did.
  expected=0
  while IFS= read -r -d '' f; do
    sz=$(du -sk "$f" | awk 'NR==1{print $1+0}')
    expected=$((expected + sz))
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0)
  got=$(preflight_find_kb "$dir" -mindepth 1 -maxdepth 1 -type d)
  [ "$got" = "$expected" ]
}

@test "preflight_find_kb sizes the match set in a bounded number of passes" {
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  local dir="$BATS_TEST_TMPDIR/count-fixture"
  mkdir -p "$dir"
  local i
  for i in $(seq 1 40); do
    printf 'data %s\n' "$i" > "$dir/f$i.txt"
  done

  # argv-recorder stubs: `find` logs each invocation then execs the real
  # binary; `du` must never run on the sizing path at all.
  local stubbin="$BATS_TEST_TMPDIR/stubbin"
  local calls="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$stubbin" "$calls"
  local real_find
  real_find="$(command -v find)"
  printf '#!/usr/bin/env bash\necho x >> "%s/find.calls"\nexec "%s" "$@"\n' "$calls" "$real_find" > "$stubbin/find"
  printf '#!/usr/bin/env bash\necho x >> "%s/du.calls"\nexit 0\n' "$calls" > "$stubbin/du"
  chmod +x "$stubbin/find" "$stubbin/du"

  local got
  got=$(PATH="$stubbin:$PATH" preflight_find_kb "$dir" -type f)
  [ -n "$got" ]
  # find runs = capability probe + matcher pass + one sizing pass — a
  # small constant, never one call per entry.
  [ -f "$calls/find.calls" ]
  local nfind
  nfind=$(wc -l < "$calls/find.calls" | tr -d ' ')
  [ "$nfind" -le 3 ]
  [ ! -s "$calls/du.calls" ]
}
