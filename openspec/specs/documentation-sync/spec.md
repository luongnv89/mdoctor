# documentation-sync Specification Delta

### Requirement: Documentation reflects shipped behavior
- Project documentation SHALL match current CLI behavior, safety controls, and quality workflows.

#### Scenario: User reads README/docs
- GIVEN a user reviewing project docs
- WHEN they look up commands/config/workflows
- THEN instructions align with current implementation.

### Requirement: Post-release maintenance notes are discoverable
- Changelog SHALL include maintenance fixes after the latest tagged release.

#### Scenario: Maintainer checks changelog
- GIVEN latest release already published
- WHEN post-release fixes are merged
- THEN an unreleased section lists those fixes.
