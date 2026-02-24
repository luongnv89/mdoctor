# Design: task-p3-1-shell-test-harness

## Approach
1. Add `tests/run.sh` as test entrypoint:
   - discovers `tests/test_*.sh`
   - runs each test in order
   - aggregates pass/fail counts

2. Add focused tests:
   - `test_command_parsing.sh`
   - `test_metadata_routing.sh`
   - `test_safety_validation.sh`
   - `test_dry_run_semantics.sh`

3. Shared assertions in `tests/helpers/assert.sh` to keep scripts concise.

4. Update `docs/DEVELOPMENT.md` with `./tests/run.sh` workflow.

## Files Affected
- `tests/run.sh`
- `tests/helpers/assert.sh`
- `tests/test_command_parsing.sh`
- `tests/test_metadata_routing.sh`
- `tests/test_safety_validation.sh`
- `tests/test_dry_run_semantics.sh`
- `docs/DEVELOPMENT.md`

## Decisions
- Keep tests bash-only, no external test framework.
- Use isolated `HOME` for tests that touch filesystem state.

## Validation Plan
- `bash -n` all test scripts
- run `./tests/run.sh`
