# custom-cleanup-scope Specification Delta

### Requirement: Configurable cleanup scope file
- The system SHALL support a configurable cleanup scope file for stale node_modules scanning.

#### Scenario: Scope file auto-creation
- GIVEN no cleanup scope file exists
- WHEN cleanup runtime initializes
- THEN a template file is created at the default scope path.

### Requirement: Include-path driven scan scope
- The system SHALL use configured include paths when provided.

#### Scenario: Custom include path
- GIVEN scope config includes `INCLUDE_PATH=~/workspace`
- WHEN stale node_modules scan runs
- THEN scan includes that workspace path.

### Requirement: Exclude-pattern filtering
- The system SHALL skip stale node_modules candidates matching exclude globs.

#### Scenario: Excluded project path
- GIVEN scope config has `EXCLUDE_GLOB=*keep-project*`
- WHEN stale node_modules scan finds candidates
- THEN matching candidate paths are skipped from deletion.
