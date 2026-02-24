# Proposal: task-p3-1-shell-test-harness

## Why
mdoctor now has non-trivial safety, logging, and scope logic. We need a runnable shell test harness to prevent regressions in command parsing, metadata routing, safety validation, and dry-run semantics.

## Scope
- In scope:
  - Add a minimal shell test harness (`tests/run.sh`) to execute isolated test scripts.
  - Add tests for command parsing/help behavior.
  - Add tests for metadata/list routing coverage.
  - Add tests for safety validation and whitelist behavior.
  - Add tests for dry-run vs force semantics for cleanup.
  - Document how to run tests locally.
- Out of scope:
  - Full CI integration matrix redesign (P3.3).
  - End-to-end tests for every cleanup module.

## Acceptance Criteria
- [x] `tests/run.sh` executes all test scripts and exits non-zero on failure.
- [x] Command parsing tests cover key help/debug/invalid-option paths.
- [x] Safety validation tests cover protected/invalid/symlink/whitelist cases.
- [x] Dry-run semantics test proves no deletion in dry-run and deletion in force mode.
- [x] Development docs include test harness usage.

## Risks
- Test flakiness due to environment differences.
  - Mitigation: isolate HOME/temp dirs and avoid host-destructive operations.
