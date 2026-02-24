# Proposal: task-p1-3-preflight-safety-summary

## Why
Before destructive cleanup runs (`--force`), operators should see exactly what areas will be touched and an estimated reclaim size to reduce accidental misuse.

## Scope
- In scope:
  - Add pre-flight safety summary for `mdoctor clean --force` module runs.
  - Add pre-flight safety summary for full cleanup force runs in `cleanup.sh --force`.
  - Include touched targets and estimated reclaim size.
- Out of scope:
  - Interactive confirmation prompt.
  - Perfect byte-accurate estimates for all modules.

## Acceptance Criteria
- [x] Force-mode module cleanup shows pre-flight summary before actions.
- [x] Force-mode full cleanup shows pre-flight summary before actions.
- [x] Summary includes touched target paths and estimated reclaim size.
- [x] Existing non-force behavior is unchanged.

## Risks
- Estimates can be approximate for age-filtered or command-based cleanups.
  - Mitigation: label output as estimate and list known non-size operations.
