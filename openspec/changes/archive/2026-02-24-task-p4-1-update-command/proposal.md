# Proposal: task-p4-1-update-command

## Why
Users currently update by re-running `install.sh`. Adding `mdoctor update` makes upgrades obvious, discoverable, and consistent with CLI-first workflows.

## Scope
- In scope:
  - Add `mdoctor update` command (stable channel).
  - Add update help output and command listing integration.
  - Implement safe git-based fast-forward update flow for install repo.
  - Add check mode to display update status without applying.
  - Update README/deployment docs with new update command.
- Out of scope:
  - Nightly/pre-release channels.
  - Auto self-update on command run.

## Acceptance Criteria
- [x] `mdoctor help` includes `update` command.
- [x] `mdoctor update --help` documents usage/options.
- [x] `mdoctor update --check` reports whether updates are available.
- [x] `mdoctor update` fast-forwards to `origin/main` when updates exist.
- [x] Docs mention update command as preferred method.

## Risks
- Running update outside a git checkout.
  - Mitigation: clear guidance and non-zero error with fallback instructions.
