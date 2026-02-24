# cleanup-safety-migration Specification Delta

### Requirement: Cleanup modules use centralized safety primitives
- The system SHALL route destructive cleanup operations through centralized safety helper functions.

#### Scenario: Directory children cleanup
- GIVEN a cleanup module targeting a cache directory
- WHEN cleanup runs
- THEN deletion executes through `safe_remove_children` and respects dry-run mode.

#### Scenario: Age-filtered cleanup
- GIVEN a cleanup module targeting files older than N days
- WHEN cleanup runs
- THEN matching paths are deleted through `safe_find_delete` with per-path validation.

### Requirement: No inline direct destructive patterns in modules
- The system SHALL avoid direct `rm -rf` and `find ... -delete/-exec rm` patterns in cleanup modules.

#### Scenario: Source audit
- GIVEN the cleanup module sources
- WHEN static checks run
- THEN no disallowed inline destructive patterns are present.
