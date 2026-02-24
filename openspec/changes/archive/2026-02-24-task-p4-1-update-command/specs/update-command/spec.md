# update-command Specification Delta

### Requirement: User-triggered stable update command
- The system SHALL provide `mdoctor update` to update installed mdoctor from stable channel.

#### Scenario: Check for updates
- GIVEN user runs `mdoctor update --check`
- WHEN remote stable branch is fetched
- THEN command reports whether local install is up to date.

#### Scenario: Apply update
- GIVEN local install is behind stable branch
- WHEN user runs `mdoctor update`
- THEN tool fast-forwards repository to latest stable commit.

### Requirement: Explicit channel handling
- The system SHALL allow explicit channel option and reject unsupported channels.

#### Scenario: Unsupported channel
- GIVEN user runs `mdoctor update --channel nightly`
- WHEN command parses options
- THEN command exits non-zero with actionable guidance.
