# Proposal: task-p4-3-safety-recovery-docs

## Why
mdoctor now has substantial safety controls (dry-run defaults, guarded deletion APIs, whitelist/scope controls, operation logs). We need explicit user docs covering safety model, recovery steps, and known limitations.

## Scope
- In scope:
  - Add dedicated safety and recovery guide.
  - Document safety layers and config controls.
  - Document incident response/recovery flow after accidental cleanup.
  - Document known limitations and non-goals.
  - Link docs from README and guidebook.
- Out of scope:
  - New runtime features.
  - Data backup automation.

## Acceptance Criteria
- [x] Dedicated safety/recovery doc exists in `docs/`.
- [x] Safety controls (dry-run, force, whitelist, scope, logs) are documented.
- [x] Recovery playbook is documented with concrete commands/paths.
- [x] Known limitations section is explicit.
- [x] README/docs index links to new safety doc.

## Risks
- Docs drifting from implementation.
  - Mitigation: tie sections to concrete file paths/command names.
