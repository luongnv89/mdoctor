# deletion-safety-primitives Specification Delta

### Requirement: Centralized deletion path validation
- The system SHALL validate deletion targets before any destructive action.

#### Scenario: Protected root path rejected
- GIVEN a deletion target `/`
- WHEN validation runs
- THEN validation fails with protected-path error.

#### Scenario: Relative or traversal path rejected
- GIVEN a deletion target containing traversal components
- WHEN validation runs
- THEN validation fails and no delete operation proceeds.

### Requirement: Safe deletion helpers honor dry-run
- The system SHALL support dry-run previews without destructive side effects.

#### Scenario: Dry-run single path
- GIVEN DRY_RUN=true and a removable file path
- WHEN `safe_remove` runs
- THEN file remains on disk and operation is logged as dry-run.

### Requirement: Safe deletion helper for scoped bulk operations
- The system SHALL provide a helper for scoped candidate deletion from a base directory.

#### Scenario: Find-based removal
- GIVEN a safe base directory and find predicate
- WHEN `safe_find_delete` runs
- THEN matching entries are processed through safe path validation before deletion.
