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
  [ -z "${DAYS_OLD:-}" ]
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

@test "DAYS_OLD is exported only when DAYS_OLD_OVERRIDE is set (issue #94)" {
  source "$ROOT_DIR/lib/context.sh"
  unset DAYS_OLD DAYS_OLD_OVERRIDE
  mdoctor_context_init
  [ -z "${DAYS_OLD:-}" ]
  export DAYS_OLD_OVERRIDE=42
  mdoctor_context_init
  [ "$DAYS_OLD" -eq 42 ]
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

@test "no SC2034 suppression survives anywhere in shell sources" {
  hits=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name mdoctor -o -name cleanup.sh -o -name doctor.sh \) -not -path "$ROOT_DIR/tests/*" | xargs grep -l 'shellcheck disable=SC2034' 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "each module directory names its required inputs" {
  for d in checks cleanups fixes; do
    sample=$(find "$ROOT_DIR/$d" -name '*.sh' | head -1)
    grep -q "Required ${d} inputs:" "$sample" || fail "$d header missing"
  done
  unlabeled=$(find "$ROOT_DIR/checks" "$ROOT_DIR/cleanups" "$ROOT_DIR/fixes" -name '*.sh' | while read -r f; do
    d=$(basename "$(dirname "$f")")
    grep -q "Required ${d} inputs:" "$f" || echo "$f"
  done)
  [ -z "$unlabeled" ]
}
