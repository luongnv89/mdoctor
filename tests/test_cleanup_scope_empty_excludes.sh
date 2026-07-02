#!/usr/bin/env bash
#
# Regression test for issue #14:
#   With set -u, iterating "${_MDOCTOR_SCOPE_EXCLUDE_GLOBS[@]}" when the array
#   has no elements aborts cleanup during the stale node_modules scan.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMPDIR_SCOPE="${ROOT_DIR}/.mdoctor-test-scope-empty.$$.$RANDOM"
mkdir -p "$TMPDIR_SCOPE"
cleanup_tmp() {
  rm -rf "$TMPDIR_SCOPE"
}
trap cleanup_tmp EXIT

SCOPE_FILE="$TMPDIR_SCOPE/cleanup_scope.conf"
cat >"$SCOPE_FILE" <<'EOF'
# No active EXCLUDE_GLOB lines — only comments (default user config).
# EXCLUDE_GLOB=*keep-project*/node_modules*
EOF

export MDOCTOR_CLEANUP_SCOPE_FILE="$SCOPE_FILE"

# Must not print "unbound variable" when exclude globs are empty.
out_file="$TMPDIR_SCOPE/out.txt"
(
  set -euo pipefail
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/cleanup_scope.sh"
  cleanup_scope_is_excluded "/tmp/some/project/node_modules" >/dev/null || true
) >"$out_file" 2>&1

assert_not_contains "$out_file" "unbound variable"

# Integration: dev_caches module completes node_modules scan phase under set -u.
SEARCH_ROOT="$TMPDIR_SCOPE/projects"
mkdir -p "$SEARCH_ROOT"
cat >"$SCOPE_FILE" <<EOF
INCLUDE_PATH=${SEARCH_ROOT}
EOF

out2="$TMPDIR_SCOPE/dev_caches.out"
(
  set -euo pipefail
  export HOME="$TMPDIR_SCOPE"
  export MDOCTOR_CLEANUP_SCOPE_FILE="$SCOPE_FILE"
  export DRY_RUN=true
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

pass "empty exclude globs do not abort cleanup scope (issue #14)"
