# cleanup-whitelist Specification Delta

### Requirement: Cleanup whitelist support
- The system SHALL support a user-configurable cleanup whitelist file.

#### Scenario: Default whitelist file creation
- GIVEN no whitelist file exists
- WHEN cleanup safety layer initializes
- THEN a template whitelist file is created under user config directory.

### Requirement: Whitelisted targets are protected
- The system SHALL skip deletion for whitelisted targets.

#### Scenario: Exact path whitelist
- GIVEN whitelist contains `~/.Trash`
- WHEN `safe_remove` is called for `~/.Trash/file.txt`
- THEN deletion is skipped and the file remains.

#### Scenario: Non-whitelisted target
- GIVEN target is not whitelisted
- WHEN cleanup runs in force mode
- THEN deletion proceeds normally.
