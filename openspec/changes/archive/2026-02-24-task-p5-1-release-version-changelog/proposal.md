# Proposal: task-p5-1-release-version-changelog

## Why
After completing P0–P4, mdoctor has substantial feature and safety improvements. We need release-ready version metadata and changelog documentation for a clean publish/tag workflow.

## Scope
- In scope:
  - Bump `MDOCTOR_VERSION` for next release.
  - Add a complete changelog entry summarizing P0–P4 outcomes.
  - Add release-readiness tracking entry in `openspec/tasks.md`.
- Out of scope:
  - Creating git tags/releases.
  - Packaging/distribution changes.

## Acceptance Criteria
- [x] `mdoctor` version is bumped for the release.
- [x] `docs/CHANGELOG.md` contains a new top release section with key additions/changes.
- [x] OpenSpec tracker includes and archives this release-prep task.
- [x] Lint/tests and `mdoctor version` pass after changes.
