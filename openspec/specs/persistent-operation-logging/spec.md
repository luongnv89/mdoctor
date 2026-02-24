# persistent-operation-logging Specification Delta

### Requirement: Persistent operation log creation
- The system SHALL create and append to a persistent operation log under user config directory.

#### Scenario: First cleanup run
- GIVEN no existing operations log file
- WHEN user runs cleanup
- THEN the log file is created and contains session records.

### Requirement: Session boundaries and summary
- The system SHALL emit start/end markers for each cleanup run.

#### Scenario: Module cleanup run
- GIVEN `mdoctor clean -m trash`
- WHEN cleanup completes
- THEN operation log includes session name, status, duration, action count, and error count.

### Requirement: Action and error event records
- The system SHALL record operation events during cleanup execution.

#### Scenario: Dry-run deletion
- GIVEN dry-run mode
- WHEN a deletion helper is called
- THEN operation log records a dry-run action event.

#### Scenario: Safety error
- GIVEN a blocked deletion target
- WHEN safety validation fails
- THEN operation log records categorized error event with target context.
