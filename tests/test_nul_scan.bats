#!/usr/bin/env bats
# Task 3.6: the stale-node_modules scan is NUL-delimited end to end, so a
# sibling directory whose name contains a newline can neither split into
# fragments nor drag important_project into safe_remove.

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
source "$ROOT_DIR/lib/cleanup_scope.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP REMOVED WEIRD
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-nulscan.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  init_colors
  # Stub safe_remove: record every candidate NUL-delimited, delete nothing.
  REMOVED="$TEST_TMP/removed.log"
  : >"$REMOVED"
  safe_remove() {
    printf '%s\0' "${1-}" >>"$REMOVED"
    return 0
  }
  source "$ROOT_DIR/cleanups/dev_caches.sh"
  # Scope the scan to our sandbox root.
  export MDOCTOR_CLEANUP_SCOPE_FILE="$TEST_TMP/scope.conf"
  printf 'INCLUDE_PATH=%s/projroot\n' "$TEST_TMP" >"$MDOCTOR_CLEANUP_SCOPE_FILE"
  # important_project is FRESH (must never reach safe_remove); the
  # newline-named sibling holds a STALE node_modules (must arrive whole).
  mkdir -p "$TEST_TMP/projroot/important_project/node_modules"
  WEIRD="$TEST_TMP/projroot/we
ird"
  mkdir -p "$WEIRD/node_modules"
  echo "stale-dep" > "$WEIRD/node_modules/stale.txt"
  touch -t 200001010000 "$WEIRD/node_modules" "$WEIRD/node_modules/stale.txt"
  NODE_MODULES_DAYS=30 clean_dev_caches >/dev/null 2>&1
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

@test "NUL-delimited scan never passes important_project to safe_remove" {
  while IFS= read -r -d '' entry; do
    case "$entry" in
      *important_project*) fail "important_project was passed to safe_remove" ;;
    esac
  done <"$REMOVED"
}

@test "newline-named node_modules arrives whole at safe_remove" {
  # Compared with a NUL-delimited read loop: grep -z is GNU-only (BSD/busybox
  # grep reject it), and no newline-based pipeline can express a name
  # containing a newline.
  local found_weird=false
  while IFS= read -r -d '' entry; do
    if [ "$entry" = "$WEIRD/node_modules" ]; then
      found_weird=true
    fi
  done <"$REMOVED"
  [ "$found_weird" = true ] || fail "newline-named node_modules was not passed whole to safe_remove"
}
