#!/usr/bin/env bash
# Task 3.6: the stale-node_modules scan is NUL-delimited end to end, so a
# sibling directory whose name contains a newline can neither split into
# fragments nor drag important_project into safe_remove.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/disk.sh"
source "$ROOT_DIR/lib/cleanup_scope.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

cd "$ROOT_DIR"
init_colors
LOGFILE="$TMPD/cleanup.log"

# Stub safe_remove: record every candidate NUL-delimited, delete nothing.
REMOVED="$TMPD/removed.log"
: >"$REMOVED"
safe_remove() {
  printf '%s\0' "${1-}" >>"$REMOVED"
  return 0
}

source "$ROOT_DIR/cleanups/dev_caches.sh"

# Scope the scan to our sandbox root.
export MDOCTOR_CLEANUP_SCOPE_FILE="$TMPD/scope.conf"
printf 'INCLUDE_PATH=%s/projroot\n' "$TMPD" >"$MDOCTOR_CLEANUP_SCOPE_FILE"

# important_project is FRESH (must never reach safe_remove); the
# newline-named sibling holds a STALE node_modules (must arrive whole).
mkdir -p "$TMPD/projroot/important_project/node_modules"
WEIRD="$TMPD/projroot/we
ird"
mkdir -p "$WEIRD/node_modules"
echo "stale-dep" > "$WEIRD/node_modules/stale.txt"
touch -t 200001010000 "$WEIRD/node_modules" "$WEIRD/node_modules/stale.txt"

NODE_MODULES_DAYS=30 clean_dev_caches >/dev/null 2>&1

# important_project never passed to safe_remove, and the newline name
# arrived as one atomic candidate. Compared with a NUL-delimited read
# loop: grep -z is GNU-only (BSD/busybox grep reject it), and no
# newline-based pipeline can express a name containing a newline.
found_weird=false
while IFS= read -r -d '' entry; do
  case "$entry" in
    *important_project*) fail "important_project was passed to safe_remove" ;;
  esac
  if [ "$entry" = "$WEIRD/node_modules" ]; then
    found_weird=true
  fi
done <"$REMOVED"
[ "$found_weird" = true ] || fail "newline-named node_modules was not passed whole to safe_remove"

pass "NUL-delimited node_modules scan"
