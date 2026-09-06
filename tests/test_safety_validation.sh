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

mkdir -p "$TMPHOME/safe"
echo "data" > "$TMPHOME/safe/file.txt"
ln -s "$TMPHOME/safe/file.txt" "$TMPHOME/safe/link.txt"

set +e
safe_remove "$TMPHOME/safe/link.txt" >/dev/null 2>&1
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
mkdir -p "$TMPHOME/.local/share/other-app"
echo "keep" > "$TMPHOME/.local/share/other-app/old.log"
touch -d '10 days ago' "$TMPHOME/.local/share/other-app/old.log"
own_log_dir="$(platform_user_log_dir)"
mkdir -p "$own_log_dir"
echo "stale" > "$own_log_dir/old.log"
touch -d '10 days ago' "$own_log_dir/old.log"
MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m logs >/dev/null 2>&1
assert_file_exists "$TMPHOME/.local/share/other-app/old.log"
assert_file_not_exists "$own_log_dir/old.log"

pass "safety validation + whitelist protection"
