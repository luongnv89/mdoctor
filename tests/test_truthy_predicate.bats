#!/usr/bin/env bats
#
# Regression test for Task 9.5 (issue #86):
# every string-boolean flag variable is routed through the is_truthy
# predicate, the predicate treats 1/yes/TRUE identically to true, and an
# unrecognised value warns and fails closed.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

# The user-facing flag variables in the named scope (every comparison site
# is `is_truthy "${VAR:-true}"); internal once-guards (_*_LOADED/_READY) are
# excluded — they are control-flow, not user flags.
FLAGS=(MDOCTOR_DEBUG MDOCTOR_PREFLIGHT_ONLY MDOCTOR_ASSUME_YES MDOCTOR_REQUIRE_TAG_SIGNATURE OPLOG_ENABLED JSON_ENABLED OP_SESSION_ACTIVE)

setup_file() {
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-truthy.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
}

teardown_file() {
  if [ -d "${TMPHOME:-}" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "truthy set: 1/yes/TRUE behave identically to true" {
  source "$ROOT_DIR/lib/constants.sh"
  for v in 1 yes TRUE true Y; do
    out=""
    is_truthy "$v" || out=$?
    [ "$out" = "" ]
  done
  for v in "" false 0 no n; do
    rc=0
    is_truthy "$v" >/dev/null 2>"$TMPHOME/unset.err" || rc=$?
    [ "$rc" -eq 1 ]
    [ ! -s "$TMPHOME/unset.err" ]
  done
}

@test "unrecognised value: warns and fails closed" {
  source "$ROOT_DIR/lib/constants.sh"
  err=""; rc=0
  err="$(is_truthy "garbage" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq "$MDOCTOR_TRUTHY_RC_UNSET" ]
  [[ "$err" == *"warning"* ]]
  [[ "$err" == *"garbage"* ]]
  err=""; rc=0
  err="$(is_truthy "maybe" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq "$MDOCTOR_TRUTHY_RC_UNSET" ]
  [[ "$err" == *"warning"* ]]
}

@test "every user-facing flag is compared via is_truthy" {
  for flag in "${FLAGS[@]}"; do
    # At least one site in the named scope compares this variable through
    # the predicate (not an ad-hoc string comparison).
    hits=$(grep -rE "is_truthy .*${flag}[^A-Za-z0-9_]" \
      "$ROOT_DIR/lib" "$ROOT_DIR/checks/storage.sh" "$ROOT_DIR/mdoctor" "$ROOT_DIR/cleanup.sh" 2>/dev/null | wc -l)
    [ "$hits" -ge 1 ]
    # And no ad-hoc string-boolean comparison survives for it.
    adhoc=$(grep -rE "${flag}[^A-Za-z0-9_].*= *\"?(true|1|yes)\"? \]" \
      "$ROOT_DIR/lib" "$ROOT_DIR/checks/storage.sh" "$ROOT_DIR/mdoctor" "$ROOT_DIR/cleanup.sh" 2>/dev/null \
      | grep -v is_truthy | wc -l)
    [ "$adhoc" -eq 0 ]
  done
}
