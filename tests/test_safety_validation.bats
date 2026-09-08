#!/usr/bin/env bats

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/safety.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME CANARY
  TMPHOME="${HOME}/.mdoctor-test-safety.$$.$RANDOM"
  mkdir -p "$TMPHOME/.config/mdoctor"
  export HOME="$TMPHOME"
  export MDOCTOR_CLEANUP_WHITELIST_FILE="$TMPHOME/.config/mdoctor/cleanup_whitelist"
  mkdir -p "$TMPHOME/.cache/safe"
  echo "data" > "$TMPHOME/.cache/safe/file.txt"
  ln -s "$TMPHOME/.cache/safe/file.txt" "$TMPHOME/.cache/safe/link.txt"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

@test "validate_deletion_path rejects / and relative paths with distinct codes" {
  local rc_root=0 rc_rel=0
  validate_deletion_path "/" >/dev/null 2>&1 || rc_root=$?
  validate_deletion_path "relative/path" >/dev/null 2>&1 || rc_rel=$?
  [ "$rc_root" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '/'"
  [ "$rc_rel" -eq "$MDOCTOR_SAFE_ERR_INVALID_TARGET" ] || fail "Expected invalid-target code for relative path"
}

@test "safe_remove blocks a direct symlink argument" {
  local rc_link=0
  safe_remove "$TMPHOME/.cache/safe/link.txt" >/dev/null 2>&1 || rc_link=$?
  [ "$rc_link" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code"
}

@test "whitelist-protected descendant survives safe_remove" {
  # Whitelist exact directory and ensure descendant is protected.
  # Assert the whitelist decision and safe_remove's documented skip
  # contract (rc=0, no deletion), not merely file survival — a renamed
  # whitelist function must fail the test, not silently pass it.
  cat > "$MDOCTOR_CLEANUP_WHITELIST_FILE" <<EOF
~/.Trash
EOF
  reload_cleanup_whitelist
  mkdir -p "$TMPHOME/.Trash"
  echo "keep" > "$TMPHOME/.Trash/protect.txt"
  DRY_RUN=false
  local rc_whitelisted=0 rc_skip=0
  is_whitelisted_cleanup_path "$TMPHOME/.Trash/protect.txt" >/dev/null 2>&1 || rc_whitelisted=$?
  [ "$rc_whitelisted" -eq 0 ] || fail "Expected whitelist match (rc=0) for descendant of whitelisted dir, got $rc_whitelisted"
  safe_remove "$TMPHOME/.Trash/protect.txt" >/dev/null 2>&1 || rc_skip=$?
  [ "$rc_skip" -eq 0 ] || fail "Expected safe_remove whitelist skip (rc=0), got $rc_skip"
  assert_file_exists "$TMPHOME/.Trash/protect.txt"
}

@test "XDG roots are protected deletion targets" {
  # Task 0.2
  local p
  local rc=0
  for p in "$TMPHOME/.local" "$TMPHOME/.local/share" "$TMPHOME/.config"; do
    rc=0
    validate_deletion_path "$p" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '$p'"
  done
}

@test "on Linux the user log dir is scoped to mdoctor's own data dir" {
  # Task 0.2
  if ! is_linux; then
    skip "Linux-only scope"
  fi
  local log_dir
  log_dir="$(platform_user_log_dir)"
  case "$log_dir" in
    */mdoctor) ;;
    *) fail "platform_user_log_dir on Linux must end in /mdoctor, got '$log_dir'" ;;
  esac
}

@test "forced logs cleanup leaves other apps' logs and cleans mdoctor's own" {
  # Task 0.2. NOTE: `touch -t` (not -d) — BSD touch has no -d flag.
  # (MDOCTOR_ASSUME_YES pre-set for the 0.5 confirmation gate.)
  mkdir -p "$TMPHOME/.local/share/other-app"
  echo "keep" > "$TMPHOME/.local/share/other-app/old.log"
  touch -t 200001010000 "$TMPHOME/.local/share/other-app/old.log"
  local own_log_dir
  own_log_dir="$(platform_user_log_dir)"
  mkdir -p "$own_log_dir"
  echo "stale" > "$own_log_dir/old.log"
  touch -t 200001010000 "$own_log_dir/old.log"
  MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m logs >/dev/null 2>&1
  assert_file_exists "$TMPHOME/.local/share/other-app/old.log"
  assert_file_not_exists "$own_log_dir/old.log"
}

@test "empty HOME fails closed — every target is protected" {
  # Task 0.3
  # shellcheck disable=SC1007 # intentional: `HOME=` (empty) is the case under test, not a typo
  local rc=0
  HOME= bash -c 'source lib/safety.sh; validate_deletion_path /Library/Caches >/dev/null 2>&1' || rc=$?
  [ "$rc" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code with empty HOME"
}

@test "denormalized whitelist forms still match after normalization" {
  # Task 0.3: normalization applies to both the candidate and every
  # whitelist entry. The scratch dir sits under an allowed root
  # ($HOME/.cache) so the allowlist (0.4) lets the calls reach the
  # whitelist check.
  cat > "$MDOCTOR_CLEANUP_WHITELIST_FILE" <<EOF
~/.cache/protected-models
EOF
  reload_cleanup_whitelist
  mkdir -p "$TMPHOME/.cache/protected-models"
  echo "weights" > "$TMPHOME/.cache/protected-models/keep.bin"
  # shellcheck disable=SC2034 # read dynamically by safe_remove via ${DRY_RUN:-true}; not visible statically
  DRY_RUN=false
  safe_remove "$TMPHOME/.cache/protected-models" >/dev/null 2>&1 || true
  safe_remove "$TMPHOME//.cache/protected-models" >/dev/null 2>&1 || true
  safe_remove "$TMPHOME/./.cache/protected-models" >/dev/null 2>&1 || true
  assert_file_exists "$TMPHOME/.cache/protected-models/keep.bin"
}

@test "paths outside every known cache/temp root are rejected" {
  # Task 0.4: even where the denylist alone would allow them.
  local p
  for p in /home /root /opt /srv /mnt /media /usr/local/bin \
    /Library/Logs/DiagnosticReports \
    "$TMPHOME/Downloads" "$TMPHOME/.config" "$TMPHOME/.local"; do
    rc=0
    validate_deletion_path "$p" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for '$p'"
  done
}

@test "every legitimate cleanup-module target is still accepted" {
  # Task 0.4: enumerated from the module list — this fails if a module
  # strays outside the allowlist or the allowlist drifts from the code.
  local p
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
    rc=0
    validate_deletion_path "$p" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "allowlist reject: '$p' rc=$rc MDOCTOR_PLATFORM=${MDOCTOR_PLATFORM:-unset} TMPDIR=${TMPDIR:-unset}"
      fail "Expected allowlist accept for legitimate target '$p' (rc=$rc)"
    fi
  done
  local dir
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    # /Library/Logs/DiagnosticReports is deliberately rejected (Task 0.4
    # acceptance) — covered by the reject list above, skipped here.
    case "$dir" in
      /Library/Logs/DiagnosticReports) continue ;;
    esac
    rc=0
    validate_deletion_path "$dir" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "Expected allowlist accept for crash dir '$dir'"
  done < <(platform_crash_dirs)
}

@test "symlinked directory argument is rejected before any glob expansion" {
  # Task 3.1: the link target's contents must survive even a forced clean
  # that reaches the same helper.
  mkdir -p "$TMPHOME/Documents" "$TMPHOME/.cache"
  echo "precious" > "$TMPHOME/Documents/keep.txt"
  ln -s "$TMPHOME/Documents" "$TMPHOME/.cache/pip"
  local rc_children=0
  safe_remove_children "$TMPHOME/.cache/pip" >/dev/null 2>&1 || rc_children=$?
  [ "$rc_children" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code for symlinked dir argument"
  assert_file_exists "$TMPHOME/Documents/keep.txt"
  MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m dev >/dev/null 2>&1 || true
  assert_file_exists "$TMPHOME/Documents/keep.txt"
  rm -f "$TMPHOME/.cache/pip"
}

@test "validation sees through symlinks to protected targets" {
  # Task 3.2: a link inside an allowed root pointing at a protected
  # target is rejected (canonicalized first).
  ln -s "$TMPHOME/Documents" "$TMPHOME/.cache/escape-link"
  local rc_escape=0
  validate_deletion_path "$TMPHOME/.cache/escape-link" >/dev/null 2>&1 || rc_escape=$?
  [ "$rc_escape" -eq "$MDOCTOR_SAFE_ERR_PROTECTED_TARGET" ] || fail "Expected protected-target code for symlink escaping to Documents"
  rm -f "$TMPHOME/.cache/escape-link"
}

@test "safe_find_delete blocks symlinks by default through the primitive" {
  # Task 3.2 (not just via safe_remove/safe_remove_children).
  mkdir -p "$TMPHOME/.cache/findtest"
  echo "stale" > "$TMPHOME/.cache/findtest/old.txt"
  touch -t 200001010000 "$TMPHOME/.cache/findtest/old.txt"
  ln -s "$TMPHOME/.cache/findtest/old.txt" "$TMPHOME/.cache/findtest/link.txt"
  touch -t 200001010000 -h "$TMPHOME/.cache/findtest/link.txt" 2>/dev/null || true
  # shellcheck disable=SC2034 # read dynamically by safe_remove via ${DRY_RUN:-true}; not visible statically
  DRY_RUN=false
  local rc_find=0
  safe_find_delete "$TMPHOME/.cache/findtest" -type l >/dev/null 2>&1 || rc_find=$?
  [ "$rc_find" -eq "$MDOCTOR_SAFE_ERR_SYMLINK_BLOCKED" ] || fail "Expected symlink-blocked code from safe_find_delete default"
  assert_file_exists "$TMPHOME/.cache/findtest/old.txt"
  # ... and deletes with the explicit opt-in.
  safe_find_delete "$TMPHOME/.cache/findtest" --allow-symlink -type l >/dev/null 2>&1
  assert_file_not_exists "$TMPHOME/.cache/findtest/link.txt"
  assert_file_exists "$TMPHOME/.cache/findtest/old.txt"
}
