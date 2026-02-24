# interactive-cleanup-mode Specification Delta

### Requirement: Interactive cleanup module selection
- The system SHALL allow users to select cleanup modules interactively.

#### Scenario: Select one module interactively
- GIVEN user runs `mdoctor clean --interactive`
- WHEN user enters a valid module index
- THEN only the selected module executes.

#### Scenario: Select all modules interactively
- GIVEN user runs `mdoctor clean --interactive`
- WHEN user enters `all`
- THEN all cleanup modules execute in order.

### Requirement: Interactive mode safety parity
- The system SHALL preserve dry-run and force semantics in interactive mode.

#### Scenario: Dry-run interactive
- GIVEN interactive mode without `--force`
- WHEN cleanup executes
- THEN no files are deleted.

#### Scenario: Force interactive
- GIVEN interactive mode with `--force`
- WHEN cleanup executes
- THEN selected cleanup operations delete eligible files.

### Requirement: Invalid selection handling
- The system SHALL reject invalid interactive selections with non-zero exit.

#### Scenario: Out-of-range index
- GIVEN user enters an invalid module index
- WHEN selection is parsed
- THEN command exits non-zero with error guidance.
