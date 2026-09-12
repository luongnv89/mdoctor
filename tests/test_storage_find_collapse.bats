#!/usr/bin/env bats
#
# Regression test for Task 11.3 (issue #97, F-PERF-006/007):
#   the dependency-dir scan makes ONE find pass over the project roots
#   with an OR-ed -name set (node_modules/venv/.venv) and -prune, so the
#   traversal stops at each match instead of descending into it; sizes
#   come from the shared chunked sizer — never a du per match — and
#   cleanups/dev_caches.sh prunes its stale-node_modules traversal the
#   same way.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup() {
  cd "$ROOT_DIR" || return 1
  export MDOCTOR_DEBUG=false
  BOLD=""; RESET=""
  export BOLD RESET
  STEP_CURRENT=0; STEP_TOTAL=1
  export STEP_CURRENT STEP_TOTAL
  ACTIONS=()
  WARN_COUNT=0; FAIL_COUNT=0
  export WARN_COUNT FAIL_COUNT
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/preflight.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  source "$ROOT_DIR/checks/storage.sh"
  init_colors >/dev/null 2>&1 || true
}

# _make_depdir_fixture WS — plain dirs plus one match of each name;
# projA/node_modules also contains a NESTED node_modules that -prune
# must hide from the match set.
_make_depdir_fixture() {
  local ws="$1"
  mkdir -p "$ws/plain/sub" \
    "$ws/projA/node_modules/pkg/inner" \
    "$ws/projA/node_modules/pkg/node_modules/deep" \
    "$ws/projB/node_modules/lib" \
    "$ws/projC/venv/lib" \
    "$ws/projD/.venv/lib/python"
  echo x > "$ws/projA/node_modules/pkg/f1"
  echo x > "$ws/projB/node_modules/f2"
  echo x > "$ws/projC/venv/f3"
  echo x > "$ws/projD/.venv/f4"
}

# _find_logger_stubbin DIR CALLS — a find stub that appends its argv to
# CALLS and delegates to the real find, plus a du stub that would record
# any call (the scan path must never make one).
_find_logger_stubbin() {
  local stubbin="$1" calls="$2" real_find
  real_find="$(command -v find)"
  mkdir -p "$stubbin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' \
    "$calls" "$real_find" > "$stubbin/find"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s.du"\nexit 0\n' \
    "$calls" > "$stubbin/du"
  chmod +x "$stubbin/find" "$stubbin/du"
}

@test "structure: one OR-ed pruned find expression in storage; dev_caches prunes too" {
  grep -qF -- '-type d \( -name node_modules -o -name venv -o -name .venv \) -prune' \
    "$ROOT_DIR/checks/storage.sh" || fail "combined pruned find expression missing"
  grep -q 'name "node_modules" -prune' "$ROOT_DIR/cleanups/dev_caches.sh" \
    || fail "dev_caches find is missing -prune"
  n_du=$(grep -c 'du -sk' "$ROOT_DIR/checks/storage.sh" || true)
  [ "$n_du" -eq 0 ]
  scan_body=$(sed -n '/^_storage_scan_depdirs()/,/^}/p' "$ROOT_DIR/checks/storage.sh")
  if printf '%s\n' "$scan_body" | grep -q 'du_size_kb\|du -sk'; then
    fail "dep-dir scan still shells out to du"
  fi
  n_old=$(grep -c '_find_and_sum(' "$ROOT_DIR/checks/storage.sh" || true)
  [ "$n_old" -eq 0 ]
}

@test "combined scan makes exactly one pruned find pass over the roots" {
  ws="$BATS_TEST_TMPDIR/ws"
  _make_depdir_fixture "$ws"
  calls="$BATS_TEST_TMPDIR/find.calls"
  stubbin="$BATS_TEST_TMPDIR/stubbin"
  _find_logger_stubbin "$stubbin" "$calls"

  PATH="$stubbin:$PATH" _storage_scan_depdirs "$ws" > /dev/null

  scans=$(grep -c -- '-prune' "$calls" || true)
  [ "$scans" -eq 1 ]
  grep -qF -- '-name node_modules -o -name venv -o -name .venv' "$calls" \
    || fail "scan pass does not carry the OR-ed name set"
  # No du anywhere on the scan path.
  [ ! -f "$calls.du" ]
}

@test "scan buckets every name once; a nested node_modules stays unvisited" {
  ws="$BATS_TEST_TMPDIR/ws"
  _make_depdir_fixture "$ws"

  _storage_scan_depdirs "$ws"

  [ "$STORAGE_DEP_NM_RC" -eq 0 ]
  [ "$STORAGE_DEP_VENV_RC" -eq 0 ]
  [ "$STORAGE_DEP_DOTVENV_RC" -eq 0 ]
  # projA + projB — the node_modules nested inside projA's match is not
  # a separate result because -prune keeps the traversal out.
  [ "$STORAGE_DEP_NM_COUNT" -eq 2 ]
  [ "$STORAGE_DEP_VENV_COUNT" -eq 1 ]
  [ "$STORAGE_DEP_DOTVENV_COUNT" -eq 1 ]
}

@test "pruned traversal visits only dirs outside matched subtrees" {
  ws="$BATS_TEST_TMPDIR/ws"
  _make_depdir_fixture "$ws"

  # Every dir the pruned expression visits (non-match dirs via the -o
  # branch; the matches themselves are visited once, then pruned).
  visited=$(find "$ws" -maxdepth 5 \
    \( -name node_modules -o -name venv -o -name .venv \) -type d -prune \
    -o -type d -print)
  n_visited=$(printf '%s\n' "$visited" | grep -c . || true)
  n_matches=$(find "$ws" -maxdepth 5 \
    \( -name node_modules -o -name venv -o -name .venv \) -type d -prune -print | grep -c . || true)
  n_unpruned=$(find "$ws" -maxdepth 5 -type d | grep -c . || true)

  # No visited path may sit inside (or be) a matched dependency dir.
  if printf '%s\n' "$visited" | grep -qE '/(node_modules|venv|\.venv)(/|$)'; then
    fail "traversal descended into a pruned match"
  fi

  # Dirs strictly inside the four matched subtrees are never visited.
  n_inside=$(find "$ws/projA/node_modules" "$ws/projB/node_modules" \
    "$ws/projC/venv" "$ws/projD/.venv" -mindepth 1 -type d | grep -c . || true)
  [ "$(( n_visited + n_matches ))" -eq "$(( n_unpruned - n_inside ))" ]
  [ "$n_visited" -lt "$n_unpruned" ]
}

@test "sizes match the old per-match du -sk totals" {
  ws="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$ws/a/node_modules/pkg" "$ws/b/node_modules" "$ws/c/venv" "$ws/d/.venv"
  dd if=/dev/zero of="$ws/a/node_modules/pkg/f.bin" bs=1024 count=64 2>/dev/null
  dd if=/dev/zero of="$ws/b/node_modules/f.bin" bs=1024 count=32 2>/dev/null
  dd if=/dev/zero of="$ws/c/venv/f.bin" bs=1024 count=48 2>/dev/null
  dd if=/dev/zero of="$ws/d/.venv/f.bin" bs=1024 count=16 2>/dev/null

  _storage_scan_depdirs "$ws"

  exp_nm=$(( $(du -sk "$ws/a/node_modules" | cut -f1) + $(du -sk "$ws/b/node_modules" | cut -f1) ))
  exp_venv=$(du -sk "$ws/c/venv" | cut -f1)
  exp_dot=$(du -sk "$ws/d/.venv" | cut -f1)
  [ "$STORAGE_DEP_NM_KB" -eq "$exp_nm" ]
  [ "$STORAGE_DEP_VENV_KB" -eq "$exp_venv" ]
  [ "$STORAGE_DEP_DOTVENV_KB" -eq "$exp_dot" ]
}

@test "BSD arm: stat-fallback sizer still matches du -sk" {
  ws="$BATS_TEST_TMPDIR/ws-bsd"
  mkdir -p "$ws/a/node_modules/pkg" "$ws/c/venv"
  dd if=/dev/zero of="$ws/a/node_modules/pkg/f.bin" bs=1024 count=64 2>/dev/null
  dd if=/dev/zero of="$ws/c/venv/f.bin" bs=1024 count=48 2>/dev/null

  stubbin="$BATS_TEST_TMPDIR/noprintf-bin"
  calls="$BATS_TEST_TMPDIR/noprintf.calls"
  real_find="$(command -v find)"
  mkdir -p "$stubbin"
  # A find that rejects -printf so the sizer exercises the stat probe.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in\n*-printf*) exit 1 ;;\nesac\nexec "%s" "$@"\n' \
    "$calls" "$real_find" > "$stubbin/find"
  chmod +x "$stubbin/find"
  unset _MDOCTOR_FIND_PRINTF_KB

  PATH="$stubbin:$PATH" _storage_scan_depdirs "$ws"

  exp_nm=$(du -sk "$ws/a/node_modules" | cut -f1)
  exp_venv=$(du -sk "$ws/c/venv" | cut -f1)
  [ "$STORAGE_DEP_NM_RC" -eq 0 ]
  [ "$STORAGE_DEP_VENV_RC" -eq 0 ]
  [ "$STORAGE_DEP_NM_KB" -eq "$exp_nm" ]
  [ "$STORAGE_DEP_VENV_KB" -eq "$exp_venv" ]
}

@test "nodedeps and devcaches share the single scan" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  ws="$BATS_TEST_TMPDIR/ws"
  _make_depdir_fixture "$ws"
  calls="$BATS_TEST_TMPDIR/find.calls"
  stubbin="$BATS_TEST_TMPDIR/stubbin"
  _find_logger_stubbin "$stubbin" "$calls"

  PATH="$stubbin:$PATH" _storage_scan_nodedeps "$ws" > /dev/null
  PATH="$stubbin:$PATH" _storage_scan_devcaches "$ws" > /dev/null

  scans=$(grep -c -- '-prune' "$calls" || true)
  [ "$scans" -eq 1 ]
  [ ! -f "$calls.du" ]
}

@test "check_storage reports node_modules and venv from the shared pass" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/Projects/p/node_modules" "$HOME/Projects/q/venv"
  dd if=/dev/zero of="$HOME/Projects/p/node_modules/f.bin" bs=1024 count=32 2>/dev/null
  dd if=/dev/zero of="$HOME/Projects/q/venv/f.bin" bs=1024 count=32 2>/dev/null
  MDOCTOR_REPORT_MIN_KB=0
  export MDOCTOR_REPORT_MIN_KB

  # Keep the e2e hermetic (the suite's HOME-sandbox contract): on macOS
  # the platform legs would walk the REAL /Applications — ~80s of
  # timeout-capped du plus host-FS state that this assertion does not
  # depend on. Only the depdirs pass and its two consumers are under
  # test here.
  _storage_scan_appdata() { :; }
  _storage_scan_applications() { :; }
  _storage_scan_devtools() { :; }
  _storage_scan_cloud() { :; }

  out=$(check_storage 2>&1)

  # Dump the captured output to the TAP stream so a failure is
  # self-diagnosing in CI (the assertion alone hides what was printed).
  printf '%s\n' "$out" >&3

  [[ "$out" == *"node_modules (1 found)"* ]]
  [[ "$out" == *"Python venv/ (1 found)"* ]]
}

@test "empty search dirs produce zeroed buckets and rc 0" {
  _storage_scan_depdirs "$BATS_TEST_TMPDIR/does-not-exist"
  rc=$?
  [ "$rc" -eq 0 ]
  [ "$STORAGE_DEP_NM_COUNT" -eq 0 ]
  [ "$STORAGE_DEP_VENV_COUNT" -eq 0 ]
  [ "$STORAGE_DEP_DOTVENV_COUNT" -eq 0 ]
}
