# shellcheck-baseline-policy Specification Delta

### Requirement: Project ShellCheck baseline policy
- The system SHALL define ShellCheck baseline policy in a repository config file.

#### Scenario: Local lint execution
- GIVEN repository root
- WHEN shell lint is run
- THEN lint uses project baseline settings from `.shellcheckrc`.

### Requirement: High-severity lint enforcement
- The system SHALL enforce high-severity shellcheck findings in CI.

#### Scenario: CI shellcheck job
- GIVEN CI shellcheck job runs
- WHEN lint script executes
- THEN shellcheck runs with error severity gate and fails on high-severity findings.

### Requirement: Single lint entrypoint
- The system SHALL provide one lint script used by both local and CI workflows.

#### Scenario: Local and CI parity
- GIVEN developer and CI both run shell lint
- WHEN linting executes
- THEN the same script and file selection rules are used.
