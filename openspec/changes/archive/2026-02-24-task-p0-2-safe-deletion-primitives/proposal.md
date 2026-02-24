# Proposal: task-p0-2-safe-deletion-primitives

## Why
Cleanup modules currently perform direct deletion operations, which increases risk of unsafe path handling. Before module-by-module migration, mdoctor needs a centralized deletion safety layer.

## Scope
- In scope:
  - Add shared deletion safety primitives in a dedicated library.
  - Add path validation rules (absolute path, traversal guard, protected path denylist, symlink policy).
  - Add safe delete helpers for single paths, directory children, and find-driven candidate sets.
  - Wire safety library into cleanup runtime (available for P0.3 migration).
- Out of scope:
  - Full cleanup module migration (P0.3).
  - New interactive UX.

## Acceptance Criteria
- [x] New safety library exists with path validation + safe delete helpers.
- [x] Protected paths are rejected with explicit error signaling.
- [x] Dry-run behavior works consistently with safety helpers.
- [x] Cleanup runtime sources the safety library successfully.
- [x] Smoke checks validate helper behavior on safe and blocked targets.

## Risks
- Overly strict validation may block legitimate cleanup targets.
  - Mitigation: start with critical-path denylist and add targeted exceptions in future tasks.
