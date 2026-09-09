#!/usr/bin/env bats

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/common.sh"

setup_file() {
  # Hermetic stubs (also set by tests/run.sh; repeated here so this file
  # passes standalone): docker/apt-get/sudo record argv, never execute.
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"
  cd "$ROOT_DIR" || return 1
  export TMPHOME TRASH_DIR
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-dryrun.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  # Use platform-aware trash directory
  TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
  if is_linux; then
    TRASH_DIR="$TMPHOME/.local/share/Trash/files"
  fi
  mkdir -p "$TRASH_DIR"
  echo "sample" > "$TRASH_DIR/sample.txt"
  mkdir -p "$TMPHOME/.config/mdoctor"
  cat > "$TMPHOME/.config/mdoctor/cleanup_whitelist" <<EOF
# empty
EOF
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "dry-run clean does not delete" {
  HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
  assert_file_exists "$TRASH_DIR/sample.txt"
}

@test "force clean deletes with assume-yes" {
  MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
  assert_file_not_exists "$TRASH_DIR/sample.txt"
}

@test "confirmation gate: no keeps the file, yes deletes it" {
  # Task 0.5
  echo "keep-no" > "$TRASH_DIR/no.txt"
  printf 'n\n' | HOME="$TMPHOME" ./mdoctor clean --force -m trash >"$TMPHOME/no.out" 2>&1 || true
  assert_file_exists "$TRASH_DIR/no.txt"
  printf 'y\n' | HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
  assert_file_not_exists "$TRASH_DIR/no.txt"
}

@test "non-tty force without assume-yes refuses and names the variable" {
  # Task 0.5
  echo "keep-null" > "$TRASH_DIR/null.txt"
  HOME="$TMPHOME" ./mdoctor clean --force -m trash < /dev/null >"$TMPHOME/null.out" 2>&1 || true
  assert_file_exists "$TRASH_DIR/null.txt"
  assert_contains "$TMPHOME/null.out" "MDOCTOR_ASSUME_YES"
}

@test "confirmation gate on the full cleanup engine refuses without answers" {
  # Task 0.5: prompt answers only — nothing is executed on refusal.
  echo "keep-engine" > "$TRASH_DIR/engine.txt"
  printf 'n\n' | HOME="$TMPHOME" ./cleanup.sh --force >"$TMPHOME/engine-no.out" 2>&1 || true
  assert_file_exists "$TRASH_DIR/engine.txt"
  HOME="$TMPHOME" ./cleanup.sh --force < /dev/null >"$TMPHOME/engine-null.out" 2>&1 || true
  assert_file_exists "$TRASH_DIR/engine.txt"
  assert_contains "$TMPHOME/engine-null.out" "MDOCTOR_ASSUME_YES"
}

@test "docker system prune requires the explicit opt-in" {
  # Task 0.6: never without MDOCTOR_ALLOW_DOCKER_PRUNE, on any module
  # path that reaches it.
  : >"$TMPHOME/prune-off.log"
  MDOCTOR_STUB_LOG="$TMPHOME/prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev_caches >/dev/null 2>&1
  assert_not_contains "$TMPHOME/prune-off.log" "docker system prune"
  MDOCTOR_STUB_LOG="$TMPHOME/prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >/dev/null 2>&1
  assert_not_contains "$TMPHOME/prune-off.log" "docker system prune"
  # ... and runs once the opt-in is set.
  : >"$TMPHOME/prune-on.log"
  MDOCTOR_STUB_LOG="$TMPHOME/prune-on.log" MDOCTOR_ALLOW_DOCKER_PRUNE=true MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev_caches >/dev/null 2>&1
  assert_contains "$TMPHOME/prune-on.log" "docker system prune -af --volumes"
}

@test "re-rated badges: trash/logs/dev/dev_caches MED, caches/downloads/browser LOW" {
  # Task 0.6
  ./mdoctor list >"$TMPHOME/list.out" 2>&1
  for m in trash logs dev dev_caches; do
    grep -q "$m.*\[MED\]" "$TMPHOME/list.out" || fail "Expected $m at [MED] in mdoctor list"
  done
  for m in caches downloads browser; do
    grep -q "$m.*\[LOW\]" "$TMPHOME/list.out" || fail "Expected $m at [LOW] in mdoctor list"
  done
}

@test "central dry-run predicate normalizes truthy spellings" {
  # Task 1.6
  source "$ROOT_DIR/lib/common.sh"
  local _rc=0
  for _v in 1 yes YES TRUE 'true '; do
    _rc=0
    DRY_RUN="$_v" is_dry_run >/dev/null 2>&1 || _rc=$?
    [ "$_rc" -eq 0 ] || fail "Expected dry-run enabled for DRY_RUN='$_v'"
  done
  for _v in 0 false FALSE no NO n N; do
    _rc=0
    DRY_RUN="$_v" is_dry_run >/dev/null 2>&1 || _rc=$?
    [ "$_rc" -eq 1 ] || fail "Expected force mode (rc 1) for DRY_RUN='$_v'"
  done
}

@test "invalid DRY_RUN warns, resolves to dry, never force" {
  source "$ROOT_DIR/lib/common.sh"
  local banana_rc=0
  DRY_RUN=banana is_dry_run >"$TMPHOME/banana.out" 2>"$TMPHOME/banana.err" || banana_rc=$?
  [ "${banana_rc:-0}" -ne 0 ] || fail "Expected non-zero predicate status for DRY_RUN=banana"
  [ "${banana_rc:-0}" -ne 1 ] || fail "Invalid DRY_RUN must never resolve to force"
  assert_contains "$TMPHOME/banana.err" "DRY_RUN"
  local dry_rc=0
  DRY_RUN=banana is_dry_run >/dev/null 2>&1 || dry_rc=$?
  [ "$dry_rc" -ne 1 ] || fail "Call-site form must stay dry for DRY_RUN=banana"
}

@test "explicit force still deletes through the real path" {
  echo "keep-force" > "$TRASH_DIR/force.txt"
  DRY_RUN=0 MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
  assert_file_not_exists "$TRASH_DIR/force.txt"
}
