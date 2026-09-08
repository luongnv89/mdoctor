#!/usr/bin/env bash
#
# tests/helpers/fixes_lane.bash
# Shared stub-PATH harness for the fixes/ test lane (issue #62).
#
# Loads the library environment a fix module expects (platform, common,
# logging, safety, colors), forces the platform branch under test via the
# exported MDOCTOR_PLATFORM predicate variable, prepends the argv-recording
# stub dirs to PATH and provides the exact-sequence assertion.
#
# Hermetic by construction: tests/run.sh prepends tests/helpers/bin
# (sudo/docker/apt-get shadowed); this loader re-prepends it together with
# tests/helpers/bin-macos so a bare `bats tests/test_fixes_lane.bats` run
# stays equally stubbed. The sudo stub records argv and refuses every
# command, so no lane test can reach a real privileged invocation.

FIX_LANE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# fix_lane_load_env — source the library stack a fix module needs, exactly
# as the mdoctor engine would before dispatching to a module function.
fix_lane_load_env() {
  # shellcheck source=/dev/null
  source "${FIX_LANE_ROOT}/lib/platform.sh"
  # shellcheck source=/dev/null
  source "${FIX_LANE_ROOT}/lib/common.sh"
  # shellcheck source=/dev/null
  source "${FIX_LANE_ROOT}/lib/logging.sh"
  # shellcheck source=/dev/null
  source "${FIX_LANE_ROOT}/lib/safety.sh"
  init_colors
  MDOCTOR_DIR="${FIX_LANE_ROOT}"
  export MDOCTOR_DIR
  # The fixes lane asserts command sequences via MDOCTOR_STUB_LOG; the
  # operations-log honour guard is issue #63 scope, so keep it off here.
  export OPLOG_ENABLED=false
}

# Platform forcing: predicates in lib/platform.sh read the exported
# MDOCTOR_PLATFORM variable, so each test pins the branch it exercises and
# the lane runs identically on macOS, Linux and Bash 3.2 CI lanes.
fix_lane_as_macos() { export MDOCTOR_PLATFORM="macos"; }
fix_lane_as_linux() { export MDOCTOR_PLATFORM="linux"; }

# fix_lane_stub_path — macOS-binary stubs first, hermetic bin/ right after.
fix_lane_stub_path() {
  export PATH="${FIX_LANE_ROOT}/tests/helpers/bin-macos:${FIX_LANE_ROOT}/tests/helpers/bin:${PATH}"
}

# fix_lane_sandbox_home BASE_DIR — sandboxed HOME under BASE_DIR/home with
# the macOS layout pre-created, so even the unprivileged cleanup steps a
# fix module triggers can only touch the sandbox. Sets HOME, LOGFILE and
# SANDBOX_HOME in the calling shell — callers must invoke it directly
# (never inside "$( ... )", which would subshell away the HOME export).
fix_lane_sandbox_home() {
  # Trust boundary: this function rm -rf's under "$1" — refuse an empty
  # or degenerate base so it can never collapse onto a system directory.
  local home="${1:-}/home"
  if [ -z "${1:-}" ] || [ "$home" = "/home" ] || [ "$home" = "/" ]; then
    echo "fix_lane_sandbox_home: non-empty BASE_DIR required, got '${1:-}'" >&2
    return 1
  fi
  rm -rf "$home"
  mkdir -p "$home/.Trash" "$home/Library/Caches" "$home/Library/Logs"
  export HOME="$home"
  export LOGFILE="$home/mdoctor.log"
  export SANDBOX_HOME="$home"
}

# fix_lane_begin LOGFILE — start one test: empty argv recorder, force mode
# so run_cmd_args really execs the stubs and the recorder sees every argv.
fix_lane_begin() {
  : >"$1"
  export MDOCTOR_STUB_LOG="$1"
  export DRY_RUN=false
}

# fix_lane_assert_sequence LOG EXPECTED_FILE — recorded argv must equal the
# expected sequence exactly, in order.
fix_lane_assert_sequence() {
  local log="$1" expected="$2" out
  out="$(mktemp "${TMPDIR:-/tmp}/mdoctor-fix-lane-diff.XXXXXX")"
  if ! diff -u "$expected" "$log" >"$out" 2>&1; then
    fail "Stub argv sequence mismatch:
$(cat "$out")"
  fi
  rm -f "$out"
}