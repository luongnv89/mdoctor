# Proposal: task-p0-3-cleanup-module-safety-migration

## Why
P0.2 introduced centralized safe deletion primitives, but cleanup modules still contained direct deletion patterns. This task migrates module-level deletion to the new safety layer.

## Scope
- In scope:
  - Refactor `cleanups/*.sh` to replace direct `rm -rf` and `find ... -delete/-exec rm` usage with `safe_remove`, `safe_remove_children`, or `safe_find_delete`.
  - Keep current command semantics and dry-run behavior.
- Out of scope:
  - Introducing whitelist/config UX (P2 tasks).
  - Non-cleanup module refactors.

## Acceptance Criteria
- [x] No direct destructive deletion patterns remain in cleanup modules.
- [x] Cleanup modules use centralized safety helpers for destructive operations.
- [x] Dry-run module smoke checks pass for all cleanup modules.
- [x] Existing command UX (`mdoctor clean -m <module>`) remains intact.

## Risks
- More conservative safety behavior may skip paths previously removed.
  - Mitigation: log skipped/blocked entries; tune policy in follow-up tasks if needed.
