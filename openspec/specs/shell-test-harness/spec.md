# shell-test-harness Specification Delta

### Requirement: Executable shell test harness
- The system SHALL provide an executable shell test harness for local regression checks.

#### Scenario: Run all tests
- GIVEN repository root
- WHEN `./tests/run.sh` is executed
- THEN all test scripts run and aggregate pass/fail status is returned.

### Requirement: Safety and dry-run regression coverage
- The system SHALL include tests for safety validation and dry-run semantics.

#### Scenario: Dry-run cleanup
- GIVEN a file in `~/.Trash`
- WHEN cleanup module runs in dry-run mode
- THEN file remains present.

#### Scenario: Force cleanup
- GIVEN a file in `~/.Trash`
- WHEN cleanup module runs in force mode
- THEN file is removed (unless whitelisted).

### Requirement: Command behavior regression coverage
- The system SHALL include tests for command help/debug parsing and module metadata routing.

#### Scenario: Help output
- GIVEN `mdoctor clean --help`
- WHEN command is executed
- THEN output includes debug and whitelist/scope guidance.
