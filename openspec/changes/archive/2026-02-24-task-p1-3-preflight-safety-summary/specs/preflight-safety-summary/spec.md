# preflight-safety-summary Specification Delta

### Requirement: Pre-flight summary before force cleanup
- The system SHALL display a safety summary before destructive cleanup execution.

#### Scenario: Module force cleanup
- GIVEN `mdoctor clean --force -m trash`
- WHEN command starts execution
- THEN it prints touched targets and estimated reclaim size before running cleanup.

#### Scenario: Full force cleanup
- GIVEN full force cleanup execution
- WHEN cleanup starts
- THEN it prints modules touched and aggregated estimated reclaim size before cleanup steps.

### Requirement: Non-force behavior unchanged
- The system SHALL not show force preflight summary in dry-run mode.

#### Scenario: Dry-run cleanup
- GIVEN `mdoctor clean` without `--force`
- WHEN command executes
- THEN no force preflight summary is printed.
