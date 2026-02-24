# safety-recovery-docs Specification Delta

### Requirement: Safety and recovery documentation
- The project SHALL provide dedicated documentation describing cleanup safety controls and recovery guidance.

#### Scenario: Review safety controls
- GIVEN a user reading docs
- WHEN they open the safety guide
- THEN they can understand dry-run, force behavior, safety guards, whitelist/scope controls, and logging.

#### Scenario: Respond to accidental cleanup
- GIVEN user suspects accidental deletion
- WHEN they follow the recovery section
- THEN they can perform concrete triage/recovery steps and understand limitations.

### Requirement: Discoverability from main docs
- The project SHALL link safety/recovery guidance from top-level docs.

#### Scenario: README docs navigation
- GIVEN a user browsing README docs links
- WHEN they look for safety guidance
- THEN they can navigate directly to the safety/recovery guide.
