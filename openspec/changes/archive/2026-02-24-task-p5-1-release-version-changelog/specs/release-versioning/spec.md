# release-versioning Specification Delta

### Requirement: Release metadata reflects completed milestone
- The system SHALL expose a bumped semantic version after major milestone completion.

#### Scenario: Version command
- GIVEN user runs `mdoctor version`
- WHEN post-milestone release prep is complete
- THEN output reflects the new release version.

### Requirement: Changelog captures milestone deliverables
- The project SHALL include a changelog entry summarizing key safety, quality, and UX improvements delivered in the milestone.

#### Scenario: Changelog review
- GIVEN maintainer reads the changelog
- WHEN preparing a tag/release
- THEN milestone capabilities are clearly summarized.
