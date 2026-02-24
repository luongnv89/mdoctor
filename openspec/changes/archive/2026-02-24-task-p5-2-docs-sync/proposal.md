# Proposal: task-p5-2-docs-sync

## Why
Recent releases added major safety/quality/UX capabilities (`update`, interactive clean, safety docs, CI lane changes, Bash 3.2 fixes). Core docs need to be synchronized so users and contributors see accurate behavior.

## Scope
- In scope:
  - Sync root README with current architecture/config/testing reality.
  - Refresh `docs/ARCHITECTURE.md` to include safety + quality layers.
  - Refresh `docs/DEVELOPMENT.md`, `docs/DEPLOYMENT.md`, and `docs/GUIDEBOOK.md` where stale.
  - Add post-2.1.0 maintenance fixes under changelog unreleased section.
- Out of scope:
  - New runtime behavior changes.
  - Full docs IA redesign.

## Acceptance Criteria
- [x] README project structure and config sections reflect current files/features.
- [x] Architecture doc reflects current command/layout and safety pipeline.
- [x] Development/deployment/guide docs reference current test and release workflows.
- [x] Changelog includes latest CI/Bash-compatibility fixes in unreleased section.
- [x] Lint/tests pass after docs sync.
