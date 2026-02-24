# debug-mode-diagnostics Specification Delta

### Requirement: Debug mode flag for operational commands
- The system SHALL support `--debug` for check, clean, and fix command flows.

#### Scenario: Check module debug
- GIVEN `mdoctor check --debug -m battery`
- WHEN command executes
- THEN debug diagnostics are emitted in structured `[DEBUG]` lines.

#### Scenario: Full cleanup debug
- GIVEN `mdoctor clean --debug`
- WHEN command executes
- THEN debug diagnostics are propagated into cleanup runtime.

### Requirement: Structured debug diagnostics
- The system SHALL emit consistent structured debug diagnostics when debug mode is enabled.

#### Scenario: Command runner debug tracing
- GIVEN debug mode is enabled
- WHEN a command runner executes a command
- THEN logs include command lifecycle debug messages.

### Requirement: Non-debug behavior unchanged
- The system SHALL preserve baseline behavior without `--debug`.

#### Scenario: Standard cleanup
- GIVEN `mdoctor clean` without `--debug`
- WHEN command executes
- THEN command behavior remains the same as before debug feature addition.
