#!/usr/bin/env bash
#
# Regression test for issue #9:
#   `mdoctor clean -f` exited silently after the pre-flight summary when a
#   target path caused `du` to fail (e.g. permission errors on items inside
#   ~/.Trash on macOS). Under `set -euo pipefail` the failing pipeline aborted
#   the script before any "Touched targets:" entries were printed.
#
# This test poisons one of the preflight target paths so `du` exits non-zero,
# then verifies the script still completes the preflight summary without
# silently exiting.
#
# Scope: this test only exercises the preflight summary in `cleanup.sh`. The
# same `du -sk ... | awk` pattern exists in several cleanup-phase modules
# (cleanups/xcode.sh, cleanups/dev_caches.sh, cleanups/ios_backups.sh,
# checks/storage.sh) and is similarly vulnerable. A follow-up issue tracks
# hardening those sites; this test does not cover them.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-preflight.$$.$RANDOM"
mkdir -p "$TMPHOME"
cleanup_tmp() {
  # Restore permissions so cleanup can succeed even if a poisoned dir was made.
  if [ -d "$TMPHOME" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}
trap cleanup_tmp EXIT

# Build a poisoned trash dir: contains a subdirectory with no read/exec perms,
# which is exactly what `du -sk` chokes on (per-item permission denied).
TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
if is_linux; then
  TRASH_DIR="$TMPHOME/.local/share/Trash/files"
fi
mkdir -p "$TRASH_DIR/poisoned"
echo "data" > "$TRASH_DIR/poisoned/file.txt"
chmod 000 "$TRASH_DIR/poisoned"

# Run preflight in dry-run; we only need the preflight section to render.
# Capture stdout+stderr; allow non-zero exit (we assert on output content).
cd "$ROOT_DIR"
out_file="$TMPHOME/preflight.out"
set +e
HOME="$TMPHOME" ./cleanup.sh --force >"$out_file" 2>&1
exit_code=$?
set -e

# Restore perms so the trap can clean up.
chmod -R u+rwx "$TMPHOME" 2>/dev/null || true

# Assert: pre-flight summary header was printed.
assert_contains "$out_file" "Pre-flight Safety Summary"

# Assert: at least one target line was printed (the bug from #9 produced an
# empty "Touched targets:" block followed by an immediate silent exit).
if ! grep -q '^  - ' "$out_file"; then
  fail "preflight emitted no '  - <path>' target lines (issue #9 regression)"
fi

# Assert: the estimated-reclaim footer was printed, proving the preflight
# function ran to completion instead of aborting mid-loop.
assert_contains "$out_file" "Estimated reclaim size:"

# The script's real cleanup phase may legitimately fail later (e.g. docker
# unreachable in CI), so we do not assert on the final exit code — only that
# the preflight section completed.
unset exit_code

pass "force-mode preflight is resilient to du permission errors (issue #9)"
