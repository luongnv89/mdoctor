#!/usr/bin/env bats
#
# Regression test for Task 9.1 (#82):
#   lib/context.sh declares the 11 module inputs; all three entry points
#   initialize it; sourcing a module without the initializer fails loudly
#   naming _MDOCTOR_CONTEXT_READY.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
source "$ROOT_DIR/lib/context.sh"
mdoctor_context_init

@test "initializer declares all 11 inputs with documented defaults" {
  source "$ROOT_DIR/lib/context.sh"
  mdoctor_context_init
  [ "$DRY_RUN" = true ]
  [ "$DAYS_OLD" -eq 7 ]
  [ "$STEP_CURRENT" -eq 0 ]
  [ "$STEP_TOTAL" -eq 1 ]
  [ "$MDOCTOR_DEBUG" = false ]
  [ "${#ACTIONS[@]}" -eq 0 ]
  [ "$WARN_COUNT" -eq 0 ]
  [ "$FAIL_COUNT" -eq 0 ]
  [ "${#LOG_PATHS[@]}" -eq 0 ]
  [ "${#LOG_DESCS[@]}" -eq 0 ]
  [ "$_MDOCTOR_CONTEXT_READY" = true ]
  grep -q "DRY_RUN.*bool" "$ROOT_DIR/lib/context.sh"
  grep -q "DAYS_OLD.*int" "$ROOT_DIR/lib/context.sh"
  grep -q "LOG_PATHS.*array" "$ROOT_DIR/lib/context.sh"
}

@test "all three entry points call the initializer" {
  grep -q "mdoctor_context_init" "$ROOT_DIR/mdoctor"
  grep -q "mdoctor_context_init" "$ROOT_DIR/cleanup.sh"
  grep -q "mdoctor_context_init" "$ROOT_DIR/doctor.sh"
}

@test "sourcing a module without the initializer fails loudly" {
  # Scrub the exported readiness flag: the negative case is a process that
  # never ran the initializer.
  run env -u _MDOCTOR_CONTEXT_READY bash -c 'source "$0/cleanups/trash.sh"' "$ROOT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"_MDOCTOR_CONTEXT_READY"* ]]
  run env -u _MDOCTOR_CONTEXT_READY bash -c 'source "$0/checks/storage.sh"' "$ROOT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"_MDOCTOR_CONTEXT_READY"* ]]
  run env -u _MDOCTOR_CONTEXT_READY bash -c 'source "$0/fixes/dns.sh"' "$ROOT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"_MDOCTOR_CONTEXT_READY"* ]]
}

@test "every module file carries the context guard" {
  missing=$(find "$ROOT_DIR/checks" "$ROOT_DIR/cleanups" "$ROOT_DIR/fixes" -name '*.sh' | while read -r f; do
    grep -q '_MDOCTOR_CONTEXT_READY' "$f" || echo "$f"
  done)
  [ -z "$missing" ]
}
