#!/usr/bin/env bats
#
# test_shell_expand.bats
# Issue #182 (PR #181 follow-up): lock in the no-eval behaviour of
# expand_source_target_vars in checks/shell.sh. $VAR and ${VAR} expand
# from the environment; command substitution ($(…)), backticks,
# process substitution (<(…)) and arithmetic ($((…))) stay literal and
# are never executed — the read-only audit must not run code from the
# audited rc file.
#
# Hermetic by construction: the helper is extracted into a fragment and
# sourced (no status_*/lib dependency), HOME is sandboxed under the
# shared fixture root, and every execution payload targets a sentinel
# file inside the sandbox whose absence proves non-execution.
# Bash 3.2 compatible (plain `[ ]` tests, no Bash 4+ constructs) so
# every test runs in the bash:3.2 container job.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-shellexp.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  sed -n '/^expand_source_target_vars()/,/^}/p' "$ROOT_DIR/checks/shell.sh" >"$TEST_TMP/expand.fn.sh"
  [ -s "$TEST_TMP/expand.fn.sh" ] || return 1
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

setup() {
  export TEST_TMP
  # shellcheck source=/dev/null
  source "$TEST_TMP/expand.fn.sh"
  local base="$TEST_TMP/$BATS_TEST_NUMBER"
  mkdir -p "$base/home"
  export HOME="$base/home"
  export TEST_BASE="$base"
  unset MDOCTOR_EXP_FOO
  unset MDOCTOR_DEFINITELY_UNSET_12345
}

@test "expands \$VAR and \${VAR} from the environment" {
  export MDOCTOR_EXP_FOO="/opt/foo"
  local got
  got="$(expand_source_target_vars '$MDOCTOR_EXP_FOO/bin')"
  [ "$got" = "/opt/foo/bin" ] || fail "bare form gave '$got'"
  got="$(expand_source_target_vars '${MDOCTOR_EXP_FOO}/bin')"
  [ "$got" = "/opt/foo/bin" ] || fail "braced form gave '$got'"
}

@test "expands unset variables to empty" {
  local got
  got="$(expand_source_target_vars 'a${MDOCTOR_DEFINITELY_UNSET_12345}b')"
  [ "$got" = "ab" ] || fail "unset var gave '$got', want 'ab'"
}

@test "leaves \$(...) literal and never executes it" {
  export MDOCTOR_EXP_SENT="$TEST_BASE/sentinel-dollar"
  local got
  got="$(expand_source_target_vars 'prefix $(touch "$MDOCTOR_EXP_SENT") suffix')"
  [ ! -e "$MDOCTOR_EXP_SENT" ] || fail "command substitution executed"
  case "$got" in
    *'$(touch "'*) : ;;
    *) fail "payload altered: '$got'" ;;
  esac
}

@test "leaves backticks literal and never executes them" {
  export MDOCTOR_EXP_SENT="$TEST_BASE/sentinel-backtick"
  local got
  got="$(expand_source_target_vars 'prefix `touch "$MDOCTOR_EXP_SENT"` suffix')"
  [ ! -e "$MDOCTOR_EXP_SENT" ] || fail "backtick substitution executed"
  case "$got" in
    *'`touch "'*) : ;;
    *) fail "payload altered: '$got'" ;;
  esac
}

@test "leaves arithmetic and process substitution literal" {
  local got
  got="$(expand_source_target_vars '$((1+1))')"
  [ "$got" = '$((1+1))' ] || fail "arithmetic altered: '$got'"
  got="$(expand_source_target_vars '<(cat /etc/hostname)')"
  [ "$got" = '<(cat /etc/hostname)' ] || fail "process substitution altered: '$got'"
}

@test "check_one_shell_file warns on missing targets without executing payloads" {
  # regression for 5ab4f85 (eval ran rc-file payloads during audit)
  status_ok() { printf 'ok %s\n' "$*" >>"$TEST_BASE/status.log"; }
  status_warn() { printf 'warn %s\n' "$*" >>"$TEST_BASE/status.log"; }
  status_info() { printf 'info %s\n' "$*" >>"$TEST_BASE/status.log"; }
  add_action() { printf 'action %s\n' "$*" >>"$TEST_BASE/status.log"; }
  step() { printf 'step %s\n' "$*" >>"$TEST_BASE/status.log"; }
  export -f status_ok status_warn status_info add_action step 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$ROOT_DIR/checks/shell.sh"
  export MDOCTOR_EXP_FOO="$TEST_BASE"
  mkdir -p "$TEST_BASE/real"
  : >"$TEST_BASE/real/ok.sh"
  printf '%s\n' 'source $MDOCTOR_EXP_FOO/real/ok.sh' 'source $(touch "$TEST_BASE/e2e-sentinel")' >"$HOME/.zshrc"
  : >"$TEST_BASE/status.log"
  check_one_shell_file ".zshrc" "sh"
  [ ! -e "$TEST_BASE/e2e-sentinel" ] || fail "rc payload executed during audit"
  grep -q 'sources missing file' "$TEST_BASE/status.log" || fail "no missing-file warning: $(cat "$TEST_BASE/status.log")"
  if grep -q 'ok.sh' "$TEST_BASE/status.log"; then
    fail "existing target warned: $(cat "$TEST_BASE/status.log")"
  fi
}
