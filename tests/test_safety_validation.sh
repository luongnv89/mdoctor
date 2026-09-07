#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

ORIG_HOME="${HOME}"
TMPHOME="${ORIG_HOME}/.mdoctor-test-safety.$$.$RANDOM"
mkdir -p "$TMPHOME"
trap 'rm -rf "$TMPHOME"' EXIT

export HOME="$TMPHOME"
export MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPHOME/.config/mdoctor/cleanup_whitelist"
mkdir -p "$TMPHOME/.config/mdoctor"

cd "$ROOT_DIR"
source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/safety.sh"

set +e
validate_deletion_path "/" >/dev/null 2>&1
rc_root=$?
validate_deletion_path "relative/path" >/dev/null 2>&1
rc_rel=$?
set -e

[ "$rc_root" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '/'"
[ "$rc_rel" -eq "$MDOCTOR_SAFE_ERR_INVALID_TARGET" ] || fail "Expected invalid-target code for relative path"

mkdir -p "$TMPHOME/.cache/safe"
echo "data" > "$TMPHOME/.cache/safe/file.txt"
ln -s "$TMPHOME/.cache/safe/file.txt" "$TMPHOME/.cache/safe/link.txt"

set +e
safe_remove "$TMPHOME/.cache/safe/link.txt" >/dev/null 2>&1
rc_link=$?
set -e
[ "$rc_link" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code"

# Whitelist exact directory and ensure descendant is protected
cat > "$MDOCTOR_CLEANUP_WHITELIST_FILE" <<EOF
~/.Trash
EOF
_MDOCTOR_WHITELIST_LOADED=false
mkdir -p "$TMPHOME/.Trash"
echo "keep" > "$TMPHOME/.Trash/protect.txt"

DRY_RUN=false
safe_remove "$TMPHOME/.Trash/protect.txt" >/dev/null 2>&1 || true
assert_file_exists "$TMPHOME/.Trash/protect.txt"

# Task 0.2: XDG roots are protected deletion targets.
set +e
for p in "$TMPHOME/.local" "$TMPHOME/.local/share" "$TMPHOME/.config"; do
  validate_deletion_path "$p" >/dev/null 2>&1
  [ "$?" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '$p'"
done
set -e

# Task 0.2: on Linux the user log dir is scoped to mdoctor's own data dir.
if is_linux; then
  log_dir="$(platform_user_log_dir)"
  case "$log_dir" in
    */mdoctor) ;;
    *) fail "platform_user_log_dir on Linux must end in /mdoctor, got '$log_dir'" ;;
  esac
fi

# Task 0.2: a forced logs cleanup leaves other apps' data alone but still
# cleans mdoctor's own log dir. (MDOCTOR_ASSUME_YES pre-set for the 0.5
# confirmation gate; ignored until it lands.)
# NOTE: `touch -t` (not -d) — BSD touch has no -d flag.
mkdir -p "$TMPHOME/.local/share/other-app"
echo "keep" > "$TMPHOME/.local/share/other-app/old.log"
touch -t 200001010000 "$TMPHOME/.local/share/other-app/old.log"
own_log_dir="$(platform_user_log_dir)"
mkdir -p "$own_log_dir"
echo "stale" > "$own_log_dir/old.log"
touch -t 200001010000 "$own_log_dir/old.log"
MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m logs >/dev/null 2>&1
assert_file_exists "$TMPHOME/.local/share/other-app/old.log"
assert_file_not_exists "$own_log_dir/old.log"

# Task 0.3: empty HOME fails closed — every target is protected.
set +e
# shellcheck disable=SC1007 # intentional: `HOME=` (empty) is the case under test, not a typo
HOME= bash -c 'source lib/safety.sh; validate_deletion_path /Library/Caches >/dev/null 2>&1'
[ "$?" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code with empty HOME"
set -e

# Task 0.3: denormalized whitelist forms still match (normalization
# applies to both the candidate and every whitelist entry). The scratch
# dir sits under an allowed root ($HOME/.cache) so the allowlist (0.4)
# lets the calls reach the whitelist check.
cat > "$MDOCTOR_CLEANUP_WHITELIST_FILE" <<EOF
~/.cache/protected-models
EOF
_MDOCTOR_WHITELIST_LOADED=false
mkdir -p "$TMPHOME/.cache/protected-models"
echo "weights" > "$TMPHOME/.cache/protected-models/keep.bin"
# shellcheck disable=SC2034 # read dynamically by safe_remove via ${DRY_RUN:-true}; not visible statically
DRY_RUN=false
safe_remove "$TMPHOME/.cache/protected-models" >/dev/null 2>&1 || true
safe_remove "$TMPHOME//.cache/protected-models" >/dev/null 2>&1 || true
safe_remove "$TMPHOME/./.cache/protected-models" >/dev/null 2>&1 || true
assert_file_exists "$TMPHOME/.cache/protected-models/keep.bin"

# Task 0.4: paths outside every known cache/temp root are rejected, even
# where the denylist alone would allow them.
set +e
for p in /home /root /opt /srv /mnt /media /usr/local/bin \
  /Library/Logs/DiagnosticReports \
  "$TMPHOME/Downloads" "$TMPHOME/.config" "$TMPHOME/.local"; do
  validate_deletion_path "$p" >/dev/null 2>&1
  [ "$?" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '$p'"
done
set -e

# Task 0.4: every path the cleanup modules legitimately target is still
# accepted (enumerated from the module list — this fails if a module
# strays outside the allowlist or the allowlist drifts from the code).
set +e
for p in \
  "$(platform_trash_dir)" \
  "$(platform_cache_dir)" \
  "$(platform_user_log_dir)" \
  "$TMPHOME/.npm" \
  "$TMPHOME/.cache/pip" \
  "$TMPHOME/.local/share/pnpm/store" \
  "$TMPHOME/.m2/repository" \
  "$TMPHOME/.gradle/caches" \
  "$TMPHOME/go/pkg/mod/cache" \
  "$TMPHOME/.cargo/registry/cache" \
  "$TMPHOME/.local/share/apport" \
  "$TMPHOME/workspace/proj/node_modules" \
  "/tmp/mdoctor-probe"; do
  validate_deletion_path "$p" >/dev/null 2>&1
  [ "$?" -eq 0 ] || fail "Expected allowlist accept for legitimate target '$p'"
done
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  # /Library/Logs/DiagnosticReports is deliberately rejected (Task 0.4
  # acceptance) — covered by the reject list above, skipped here.
  case "$dir" in
    /Library/Logs/DiagnosticReports) continue ;;
  esac
  validate_deletion_path "$dir" >/dev/null 2>&1
  [ "$?" -eq 0 ] || fail "Expected allowlist accept for crash dir '$dir'"
done < <(platform_crash_dirs)
set -e

# Task 3.1: a symlinked directory argument is rejected (code 23) before
# any glob expansion — the link target's contents must survive even a
# forced clean that reaches the same helper.
mkdir -p "$TMPHOME/Documents" "$TMPHOME/.cache"
echo "precious" > "$TMPHOME/Documents/keep.txt"
ln -s "$TMPHOME/Documents" "$TMPHOME/.cache/pip"
set +e
safe_remove_children "$TMPHOME/.cache/pip" >/dev/null 2>&1
[ "$?" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code for symlinked dir argument"
set -e
assert_file_exists "$TMPHOME/Documents/keep.txt"
MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >/dev/null 2>&1 || true
assert_file_exists "$TMPHOME/Documents/keep.txt"
rm -f "$TMPHOME/.cache/pip"

# Task 3.2: validation sees through symlinks — a link inside an allowed
# root pointing at a protected target is rejected (canonicalized first).
ln -s "$TMPHOME/Documents" "$TMPHOME/.cache/escape-link"
set +e
validate_deletion_path "$TMPHOME/.cache/escape-link" >/dev/null 2>&1
[ "$?" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for symlink escaping to Documents"
set -e
rm -f "$TMPHOME/.cache/escape-link"

# Task 3.2: safe_find_delete blocks symlinks by default through the
# primitive (not just via safe_remove/safe_remove_children).
mkdir -p "$TMPHOME/.cache/findtest"
echo "stale" > "$TMPHOME/.cache/findtest/old.txt"
touch -t 200001010000 "$TMPHOME/.cache/findtest/old.txt"
ln -s "$TMPHOME/.cache/findtest/old.txt" "$TMPHOME/.cache/findtest/link.txt"
touch -t 200001010000 -h "$TMPHOME/.cache/findtest/link.txt" 2>/dev/null || true
# shellcheck disable=SC2034 # read dynamically by safe_remove via ${DRY_RUN:-true}; not visible statically
DRY_RUN=false
set +e
safe_find_delete "$TMPHOME/.cache/findtest" -type l >/dev/null 2>&1
[ "$?" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code from safe_find_delete default"
set -e
assert_file_exists "$TMPHOME/.cache/findtest/old.txt"
# ... and deletes with the explicit opt-in.
safe_find_delete "$TMPHOME/.cache/findtest" --allow-symlink -type l >/dev/null 2>&1
assert_file_not_exists "$TMPHOME/.cache/findtest/link.txt"
assert_file_exists "$TMPHOME/.cache/findtest/old.txt"

pass "safety validation + whitelist protection"
