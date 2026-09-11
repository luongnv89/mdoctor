#!/usr/bin/env bats
#
# Regression test for issue #94 (F-CLEAN-015):
#   per-module staleness thresholds (7/30/90) are reachable — the DAYS_OLD
#   global is exported only when DAYS_OLD_OVERRIDE is present, so each
#   module's own documented ${DAYS_OLD:-N} default applies. The second
#   threshold (DAYS_OLD_NODE_MODULES) follows the same naming scheme and
#   both are listed in the help's environment-variable section.
#
# Hermetic: HOME sandbox, dry-run everywhere. Modules print their age in
# the header before any dir checks, so the probes never touch real state.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup() {
  cd "$ROOT_DIR" || return 1
  export MDOCTOR_DIR="$ROOT_DIR"
  export MDOCTOR_DEBUG=false
  unset DAYS_OLD DAYS_OLD_OVERRIDE
  source "$ROOT_DIR/lib/context.sh"
  mdoctor_context_init
  BOLD=""
  RESET=""
  export BOLD RESET
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export DRY_RUN=true
  export LOGFILE="$HOME/mdoctor.log"
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  source "$ROOT_DIR/lib/help.sh"
  source "$ROOT_DIR/lib/safety.sh"
  source "$ROOT_DIR/lib/cleanup_scope.sh"
  source "$ROOT_DIR/lib/clean_common.sh"
  register_all_modules
}

error() { echo "Error: $*" >&2; }

# _run_module MODULE — source the module file and run its function so the
# header (which states the effective age threshold) prints in dry-run.
_run_module() {
  source "$ROOT_DIR/cleanups/$1.sh"
  case "$1" in
    logs) clean_logs ;;
    downloads) clean_downloads_large_files ;;
    crash_reports) clean_crash_reports ;;
    xcode) clean_xcode ;;
    ios_backups) clean_ios_backups ;;
  esac
}

@test "per-module defaults apply when no override is set (issue #94)" {
  # logs and downloads (7), crash_reports and xcode (30), ios_backups (90).
  assert_run_days() {
    local mod="$1" want="$2"
    run _run_module "$mod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"older than ${want} days"* ]] || fail "$mod header missing 'older than ${want} days'"
  }
  assert_run_days logs 7
  assert_run_days downloads 7
  assert_run_days crash_reports 30
  assert_run_days xcode 30
  assert_run_days ios_backups 90
}

@test "DAYS_OLD_OVERRIDE wins over every module default (issue #94)" {
  export DAYS_OLD_OVERRIDE=365
  mdoctor_context_init
  for mod in logs downloads crash_reports xcode ios_backups; do
    run _run_module "$mod"
    [ "$status" -eq 0 ]
    [[ "$output" == *"older than 365 days"* ]] || fail "$mod header missing overridden 'older than 365 days'"
  done
}

@test "mdoctor clean -m ios_backups applies the documented 90-day default (issue #94)" {
  if ! is_macos; then
    skip "ios_backups is macOS-only"
  fi
  unset DAYS_OLD DAYS_OLD_OVERRIDE
  run "$ROOT_DIR/mdoctor" clean -m ios_backups
  [ "$status" -eq 0 ]
  [[ "$output" == *"older than 90 days"* ]]
}

@test "both thresholds share the DAYS_OLD naming scheme and appear in help (issue #94)" {
  # dev_caches uses the renamed DAYS_OLD_* variable.
  grep -q 'DAYS_OLD_NODE_MODULES' "$ROOT_DIR/cleanups/dev_caches.sh" || fail "dev_caches missing DAYS_OLD_NODE_MODULES"
  if grep -q 'NODE_MODULES_DAYS' "$ROOT_DIR/cleanups/dev_caches.sh"; then
    fail "old NODE_MODULES_DAYS name survived in dev_caches.sh"
  fi
  # Both thresholds in main help and in clean --help.
  run "$ROOT_DIR/mdoctor" help
  [[ "$output" == *"DAYS_OLD_OVERRIDE"* ]] || fail "main help missing DAYS_OLD_OVERRIDE"
  [[ "$output" == *"DAYS_OLD_NODE_MODULES"* ]] || fail "main help missing DAYS_OLD_NODE_MODULES"
  run "$ROOT_DIR/mdoctor" clean --help
  [[ "$output" == *"DAYS_OLD_OVERRIDE"* ]] || fail "clean --help missing DAYS_OLD_OVERRIDE"
  [[ "$output" == *"DAYS_OLD_NODE_MODULES"* ]] || fail "clean --help missing DAYS_OLD_NODE_MODULES"
  [[ "$output" != *"NODE_MODULES_DAYS"* ]] || fail "clean --help still shows old NODE_MODULES_DAYS"
}