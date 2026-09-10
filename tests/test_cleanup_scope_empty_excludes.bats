#!/usr/bin/env bats
#
# Regression test for issue #14:
#   With set -u, iterating "${_MDOCTOR_SCOPE_EXCLUDE_GLOBS[@]}" when the array
#   has no elements aborts cleanup during the stale node_modules scan.
#

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPDIR_SCOPE SCOPE_FILE
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPDIR_SCOPE="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-scope-empty.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPDIR_SCOPE"
  SCOPE_FILE="$TMPDIR_SCOPE/cleanup_scope.conf"
  cat >"$SCOPE_FILE" <<'EOF'
# No active EXCLUDE_GLOB lines — only comments (default user config).
# EXCLUDE_GLOB=*keep-project*/node_modules*
EOF
  export MDOCTOR_CLEANUP_SCOPE_FILE="$SCOPE_FILE"
}

teardown_file() {
  rm -rf "$TMPDIR_SCOPE"
}

@test "empty exclude globs print no unbound-variable error" {
  # Must not print "unbound variable" when exclude globs are empty.
  out_file="$TMPDIR_SCOPE/out.txt"
  (
    set -euo pipefail
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    cleanup_scope_is_excluded "/tmp/some/project/node_modules" >/dev/null || true
  ) >"$out_file" 2>&1
  assert_not_contains "$out_file" "unbound variable"
}

@test "dev_caches scan completes with empty exclude globs under set -u" {
  SEARCH_ROOT="$TMPDIR_SCOPE/projects"
  mkdir -p "$SEARCH_ROOT"
  cat >"$SCOPE_FILE" <<EOF
INCLUDE_PATH=${SEARCH_ROOT}
EOF
  # Force mode (not dry-run): the stale-node_modules removal half must
  # actually execute — exporting DRY_RUN=true here used to skip every
  # deletion, covering only the scan half of the fix (issue #72). The
  # canary lives under the sandboxed HOME, and the safety policy allows
  # "<project>/node_modules" targets there, so force execution is safe.
  mkdir -p "$SEARCH_ROOT/oldproj/node_modules"
  echo "stale" > "$SEARCH_ROOT/oldproj/node_modules/stale.js"
  touch -d "40 days ago" "$SEARCH_ROOT/oldproj/node_modules" 2>/dev/null \
    || touch -t 202001010000 "$SEARCH_ROOT/oldproj/node_modules"
  out2="$TMPDIR_SCOPE/dev_caches.out"
  (
    set -euo pipefail
    export HOME="$TMPDIR_SCOPE"
    export MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPDIR_SCOPE/.config/mdoctor/cleanup_whitelist"
    export MDOCTOR_CLEANUP_SCOPE_FILE="$SCOPE_FILE"
    export LOGFILE="$TMPDIR_SCOPE/mdoctor.log"
    DRY_RUN=false
    export NODE_MODULES_DAYS=30
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/platform.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/common.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/logging.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/disk.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/safety.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/cleanups/dev_caches.sh"
    clean_dev_caches
  ) >"$out2" 2>&1
  assert_not_contains "$out2" "unbound variable"
  assert_contains "$out2" "Scanning for stale node_modules"
  # The removal half executed: the stale canary is gone.
  assert_file_not_exists "$SEARCH_ROOT/oldproj/node_modules"
}
