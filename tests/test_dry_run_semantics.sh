#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/platform.sh"

# Hermetic stubs (also set by tests/run.sh; repeated here so this file
# passes standalone): docker/apt-get/sudo record argv, never execute.
export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-dryrun.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

# Use platform-aware trash directory
TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
if is_linux; then
  TRASH_DIR="$TMPHOME/.local/share/Trash/files"
fi
mkdir -p "$TRASH_DIR"
echo "sample" > "$TRASH_DIR/sample.txt"

cd "$ROOT_DIR"

# Dry-run should not delete
HOME="$TMPHOME" ./mdoctor clean -m trash >/dev/null 2>&1
assert_file_exists "$TRASH_DIR/sample.txt"

# Force should delete (no whitelist); assume-yes skips the 0.5 prompt.
mkdir -p "$TMPHOME/.config/mdoctor"
cat > "$TMPHOME/.config/mdoctor/cleanup_whitelist" <<EOF
# empty
EOF
MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
assert_file_not_exists "$TRASH_DIR/sample.txt"

# Task 0.5: confirmation gate — "no" keeps the file, "yes" deletes it.
echo "keep-no" > "$TRASH_DIR/no.txt"
printf 'n\n' | HOME="$TMPHOME" ./mdoctor clean --force -m trash >"$TMPHOME/no.out" 2>&1 || true
assert_file_exists "$TRASH_DIR/no.txt"
printf 'y\n' | HOME="$TMPHOME" ./mdoctor clean --force -m trash >/dev/null 2>&1
assert_file_not_exists "$TRASH_DIR/no.txt"

# Task 0.5: non-tty force without the assume-yes variable refuses and
# names the variable.
echo "keep-null" > "$TRASH_DIR/null.txt"
HOME="$TMPHOME" ./mdoctor clean --force -m trash < /dev/null >"$TMPHOME/null.out" 2>&1 || true
assert_file_exists "$TRASH_DIR/null.txt"
assert_contains "$TMPHOME/null.out" "MDOCTOR_ASSUME_YES"

# Task 0.5: same gate on the full cleanup engine (prompt answers only —
# nothing is executed on refusal).
echo "keep-engine" > "$TRASH_DIR/engine.txt"
printf 'n\n' | HOME="$TMPHOME" ./cleanup.sh --force >"$TMPHOME/engine-no.out" 2>&1 || true
assert_file_exists "$TRASH_DIR/engine.txt"
HOME="$TMPHOME" ./cleanup.sh --force < /dev/null >"$TMPHOME/engine-null.out" 2>&1 || true
assert_file_exists "$TRASH_DIR/engine.txt"
assert_contains "$TMPHOME/engine-null.out" "MDOCTOR_ASSUME_YES"

# Task 0.6: `docker system prune` never runs without the explicit opt-in,
# on any module path that reaches it.
: >"$TMPHOME/prune-off.log"
MDOCTOR_STUB_LOG="$TMPHOME/prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev_caches >/dev/null 2>&1
assert_not_contains "$TMPHOME/prune-off.log" "docker system prune"
MDOCTOR_STUB_LOG="$TMPHOME/prune-off.log" MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >/dev/null 2>&1
assert_not_contains "$TMPHOME/prune-off.log" "docker system prune"
# ... and runs once the opt-in is set.
: >"$TMPHOME/prune-on.log"
MDOCTOR_STUB_LOG="$TMPHOME/prune-on.log" MDOCTOR_ALLOW_DOCKER_PRUNE=true MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev_caches >/dev/null 2>&1
assert_contains "$TMPHOME/prune-on.log" "docker system prune -af --volumes"

# Task 0.6: re-rated badges — trash/logs/dev/dev_caches above LOW, and
# the remaining LOW modules delete no user files (caches, downloads,
# browser only).
./mdoctor list >"$TMPHOME/list.out" 2>&1
for m in trash logs dev dev_caches; do
  grep -q "$m.*\[MED\]" "$TMPHOME/list.out" || fail "Expected $m at [MED] in mdoctor list"
done
for m in caches downloads browser; do
  grep -q "$m.*\[LOW\]" "$TMPHOME/list.out" || fail "Expected $m at [LOW] in mdoctor list"
done

pass "dry-run vs force semantics"
