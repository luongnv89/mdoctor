# Proposal: task-p4-2-interactive-cleanup-mode

## Why
Some users want a guided cleanup flow instead of memorizing module names. Interactive mode makes selective cleanup safer and more user-friendly.

## Scope
- In scope:
  - Add `mdoctor clean --interactive` module selection flow.
  - Support selection by indices or `all`.
  - Respect existing dry-run/force behavior.
  - Add regression test for interactive selection flow.
  - Update README usage docs.
- Out of scope:
  - Full-screen TUI.
  - Per-item file-level selection.

## Acceptance Criteria
- [x] `mdoctor clean --help` documents interactive mode.
- [x] `mdoctor clean --interactive` prompts and runs selected module(s).
- [x] Interactive mode supports `all` and validates invalid selections.
- [x] Dry-run vs force behavior remains correct in interactive mode.
- [x] Tests cover interactive selection behavior.

## Risks
- Prompt output interfering with selection parsing in scripted runs.
  - Mitigation: print prompt UI to stderr and keep machine-consumable output separate.
