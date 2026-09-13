#!/usr/bin/env bats
#
# test_no_color_tty_guard.bats
# Issue #108 (Task 12.5): ANSI escapes must never leak into piped or
# redirected output, and NO_COLOR / MDOCTOR_NO_COLOR must suppress color
# on a tty. The `[ -t 1 ]` guard and the NO_COLOR check live inside
# mdoctor_term_init (lib/constants.sh), the memoized engine behind
# init_colors — the single color implementation every entry point calls.
#
# Hermetic: HOME is sandboxed under the shared fixture root; the tty legs
# run through script(1) — the same forced-tty helper test_exit_hooks.bats
# and test_install_safety.bats use — and skip cleanly where script(1),
# tput, or a working TERM=xterm terminfo entry is absent. The full
# `check --json` audit runs once in setup_file and is shared by the JSON
# pipeline test. Bash 3.2 compatible (plain `[ ]`, no [[ =~ ]]).
#

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

# Per-command timeout (seconds) so a slow probe can never hang the file.
_CMD_TIMEOUT=280

_run_with_timeout() {
  # Same shape as test_e2e_safe_mode.bats: GNU timeout, gtimeout, or bare.
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

_pty_run() {
  # _pty_run INNER_CMD — run INNER_CMD through script(1) on a real pty;
  # the child sees `[ -t 1 ]` true. The pty transcript (stdout+stderr of
  # the child) lands on our stdout.
  local inner="$1"
  if is_macos; then
    script -q /dev/null sh -c "$inner" </dev/null
  else
    script -qec "$inner" /dev/null </dev/null
  fi
}

_esc_lines() {
  # Count input lines containing a raw ESC byte — cat -v renders each as
  # the two literal characters '^[', which the issue's verify greps for.
  cat -v | grep -c '\^\[\[' || true
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP PTY_OK JSON_RUN_RC
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-nocolor.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  mkdir -p "$TEST_TMP/home"

  # Pty capability gate: the tty legs need script(1), tput, and a TERM
  # whose terminfo entry actually emits SGR — a minimal container missing
  # any of them skips those tests instead of going falsely red.
  PTY_OK=false
  if command -v script >/dev/null 2>&1 && command -v tput >/dev/null 2>&1; then
    if [ -n "$(env TERM=xterm tput setaf 1 2>/dev/null)" ]; then
      PTY_OK=true
    fi
  fi

  # Shared full audit (acceptance criterion: `check --json` stays a clean
  # document when piped). One run, recorded for the JSON test below.
  JSON_RUN_RC=0
  HOME="$TEST_TMP/home" _run_with_timeout "$ROOT_DIR/mdoctor" check --json \
    >"$TEST_TMP/check.json" 2>"$TEST_TMP/check.err" || JSON_RUN_RC=$?
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

_require_pty() {
  if [ "${PTY_OK:-false}" != true ]; then
    skip "script(1)/tput/terminfo unavailable for the pty leg"
  fi
}

@test "piped 'check -m network' emits no ANSI escapes" {
  # AC: ./mdoctor check -m network | cat -v shows zero '^[[' sequences.
  local out="$TEST_TMP/piped.out"
  HOME="$TEST_TMP/home" _run_with_timeout "$ROOT_DIR/mdoctor" check -m network \
    >"$out" 2>/dev/null || fail "check -m network exited non-zero on a pipe"
  [ -s "$out" ] || fail "check -m network produced no output"
  local esc
  esc="$(_esc_lines <"$out")"
  [ "$esc" -eq 0 ] || fail "piped output carries $esc ANSI-escape line(s)"
}

@test "pty run emits escapes when color is not opted out (control)" {
  # Positive control: proves the pty harness actually exercises the color
  # path, so the NO_COLOR legs below assert a real suppression.
  _require_pty
  local out="$TEST_TMP/pty-control.out"
  _pty_run "env TERM=xterm HOME='$TEST_TMP/home' '$ROOT_DIR/mdoctor' check -m network" \
    >"$out" 2>/dev/null || true
  [ -s "$out" ] || fail "pty run produced no output"
  local esc
  esc="$(_esc_lines <"$out")"
  [ "$esc" -gt 0 ] || fail "expected ANSI escapes on a tty without NO_COLOR — got none"
}

@test "NO_COLOR=1 suppresses escapes on a tty" {
  # AC: NO_COLOR=1 ./mdoctor check -m network on a tty emits no escapes.
  _require_pty
  local out="$TEST_TMP/pty-nocolor.out"
  _pty_run "env TERM=xterm NO_COLOR=1 HOME='$TEST_TMP/home' '$ROOT_DIR/mdoctor' check -m network" \
    >"$out" 2>/dev/null || true
  [ -s "$out" ] || fail "pty NO_COLOR run produced no output"
  local esc
  esc="$(_esc_lines <"$out")"
  [ "$esc" -eq 0 ] || fail "NO_COLOR=1 on a tty still emitted $esc escape line(s)"
}

@test "MDOCTOR_NO_COLOR=1 behaves identically on a tty" {
  # AC: MDOCTOR_NO_COLOR=1 behaves identically to NO_COLOR=1.
  _require_pty
  local out="$TEST_TMP/pty-mdoctor-nocolor.out"
  _pty_run "env TERM=xterm MDOCTOR_NO_COLOR=1 HOME='$TEST_TMP/home' '$ROOT_DIR/mdoctor' check -m network" \
    >"$out" 2>/dev/null || true
  [ -s "$out" ] || fail "pty MDOCTOR_NO_COLOR run produced no output"
  local esc
  esc="$(_esc_lines <"$out")"
  [ "$esc" -eq 0 ] || fail "MDOCTOR_NO_COLOR=1 on a tty still emitted $esc escape line(s)"
}

@test "piped 'check --json' parses through python3 -m json.tool" {
  # AC: ./mdoctor check --json | python3 -m json.tool succeeds when piped.
  [ "$JSON_RUN_RC" -eq 0 ] || {
    tail -n 20 "$TEST_TMP/check.err" >&2 || true
    fail "shared 'mdoctor check --json' exited $JSON_RUN_RC (expected 0)"
  }
  [ -s "$TEST_TMP/check.json" ] || fail "check --json produced no output"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool <"$TEST_TMP/check.json" >/dev/null \
      || fail "python3 -m json.tool rejected the piped --json document"
  elif command -v jq >/dev/null 2>&1; then
    jq empty "$TEST_TMP/check.json" >/dev/null 2>&1 \
      || fail "jq rejected the piped --json document"
  else
    skip "no JSON parser available (need python3 or jq)"
  fi
}

@test "init_colors is the single color implementation at startup" {
  # AC: callers route through init_colors — the engine mdoctor_term_init
  # may only be defined in lib/constants.sh and delegated to from
  # lib/common.sh's init_colors body. Nothing else may invoke it.
  local hits
  hits="$(grep -rn 'mdoctor_term_init' mdoctor doctor.sh cleanup.sh install.sh uninstall.sh lib checks cleanups fixes 2>/dev/null \
    | grep -v 'lib/constants\.sh' \
    | grep -v 'lib/common\.sh' || true)"
  [ -z "$hits" ] || fail "mdoctor_term_init bypasses init_colors at: $hits"

  # mdoctor's startup COLORS block must call init_colors — the single
  # implementation — before any command work, never after a tty-safe
  # block that could be overwritten later.
  local init_line dispatch_line
  init_line="$(grep -n '^init_colors$' mdoctor | head -1 | cut -d: -f1)"
  [ -n "$init_line" ] || fail "mdoctor top level never calls init_colors"
  dispatch_line="$(grep -n 'MAIN DISPATCH' mdoctor | head -1 | cut -d: -f1)"
  [ -n "$dispatch_line" ] || fail "MAIN DISPATCH marker missing in mdoctor"
  [ "$init_line" -lt "$dispatch_line" ] \
    || fail "init_colors (line $init_line) runs after dispatch (line $dispatch_line)"
}

@test "unit: init_colors leaves colors empty and still sets icons (non-tty)" {
  # On a non-tty the color variables stay empty — but the status icons
  # are plain glyphs, not escapes, so they must still be populated.
  ( cd "$ROOT_DIR" && bash -c '
    source lib/common.sh
    init_colors
    [ -z "$RED" ] && [ -z "$GREEN" ] && [ -z "$RESET" ] \
      && [ -n "$CHECK" ] && [ -n "$WARN" ]
  ' ) || fail "init_colors on a non-tty should empty colors but keep icons"
}

@test "unit: NO_COLOR skips the tput probe entirely" {
  # Even where a tput exists on PATH, NO_COLOR must stop init_colors from
  # reaching it — the decision memoizes before the probe. A stub tput
  # records any invocation.
  mkdir -p "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/tput" <<'EOF'
#!/usr/bin/env bash
printf 'tput %s\n' "$*" >> "${MDOCTOR_TPUT_LOG:-/dev/null}"
printf '\033[31m'
EOF
  chmod +x "$TEST_TMP/bin/tput"
  rm -f "$TEST_TMP/tput.log"
  ( cd "$ROOT_DIR" && env PATH="$TEST_TMP/bin:$PATH" \
      MDOCTOR_TPUT_LOG="$TEST_TMP/tput.log" NO_COLOR=1 \
      bash -c 'source lib/common.sh; init_colors' ) \
    || fail "init_colors failed under NO_COLOR=1"
  [ ! -f "$TEST_TMP/tput.log" ] \
    || fail "tput probe ran despite NO_COLOR=1: $(cat "$TEST_TMP/tput.log")"
}
