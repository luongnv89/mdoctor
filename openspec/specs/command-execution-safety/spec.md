# command-execution-safety Specification Delta

### Requirement: Safe command execution primitive
- The system SHALL execute operational shell commands without using `eval` in the shared command runner.

#### Scenario: Normal execution
- GIVEN mdoctor runs in force mode
- WHEN a cleanup module triggers a command through shared runner
- THEN the command executes and exit status is propagated without `eval`.

#### Scenario: Dry-run execution
- GIVEN mdoctor runs in dry-run mode
- WHEN a cleanup module triggers a command through shared runner
- THEN the command is logged as preview and not executed.

### Requirement: Backward compatibility during migration
- The system SHALL preserve behavior for existing single-string runner calls during transitional migration.

#### Scenario: Legacy string caller
- GIVEN a module still calls runner with a single command string
- WHEN command execution is invoked
- THEN command still runs through legacy compatibility path and logs deprecation context.
