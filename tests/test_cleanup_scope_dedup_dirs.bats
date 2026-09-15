#!/usr/bin/env bats
#
# Regression test for issue #204:
#   cleanup_scope_get_search_dirs could emit the same physical directory
#   twice — the default candidate list carries both "${HOME}/Projects"
#   and "${HOME}/projects", which resolve to one directory on
#   case-insensitive filesystems (default APFS), so the dev_caches
#   node_modules sweep walked it once per spelling and double-counted
#   every match. e23abef fixed the identical defect in
#   checks/storage.sh::_storage_search_dirs (issue #97); the same
#   device:inode dedup now guards the cleanup-scope list.
#
# A symlink alias is the same device:inode pair and exercises the dedupe
# portably on any filesystem.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-scope-dedup.$(fixture_run_id).XXXXXX")"
  export TEST_TMP
  fixture_trap_cleanup "$TEST_TMP"
  TEST_HOME="$TEST_TMP/home"
  mkdir -p "$TEST_HOME/Projects"
  # "$TEST_HOME/projects" is a second spelling of the same physical dir.
  ln -s "$TEST_HOME/Projects" "$TEST_HOME/projects"
  export TEST_HOME
  SCOPE_FILE="$TEST_TMP/cleanup_scope.conf"
  export SCOPE_FILE
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

# _scope_dirs — the search-dir list exactly as dev_caches consumes it,
# under the fixture HOME and scope file.
_scope_dirs() {
  (
    export HOME="$TEST_HOME"
    export MDOCTOR_CLEANUP_SCOPE_FILE="$SCOPE_FILE"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/constants.sh"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    cleanup_scope_get_search_dirs
  )
}

@test "default scope emits each physical root once across spelling aliases" {
  : >"$SCOPE_FILE" # no INCLUDE_PATH lines → default candidate list
  out="$(_scope_dirs)"
  # The real dir is emitted once; its alias spelling is deduped away.
  [ "$(printf '%s\n' "$out" | grep -xc "$TEST_HOME/Projects")" -eq 1 ]
  [ "$(printf '%s\n' "$out" | grep -xc "$TEST_HOME/projects")" -eq 0 ]
  # The remaining candidates are unaffected: six spellings in, five out.
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 5 ]
}

@test "configured INCLUDE_PATH lines dedupe the same physical dir" {
  cat >"$SCOPE_FILE" <<EOF
INCLUDE_PATH=$TEST_HOME/Projects
INCLUDE_PATH=$TEST_HOME/projects
EOF
  out="$(_scope_dirs)"
  [ "$out" = "$TEST_HOME/Projects" ]
}

@test "nonexistent candidates still emit (consumer owns the -d filter)" {
  : >"$SCOPE_FILE"
  out="$(_scope_dirs)"
  # code/workspace/dev/src do not exist under the fixture HOME; the
  # dedupe must not silently drop candidates it cannot stat.
  printf '%s\n' "$out" | grep -qx "$TEST_HOME/code"
}
