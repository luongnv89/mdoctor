# destructive-error-taxonomy Specification Delta

### Requirement: Standardized destructive failure taxonomy
- The system SHALL classify destructive-operation failures into consistent categories.

#### Scenario: Protected target
- GIVEN a target `/`
- WHEN validation runs
- THEN the operation fails with protected-target category code.

#### Scenario: Symlink blocked
- GIVEN a symlink path without explicit allow flag
- WHEN `safe_remove` runs
- THEN the operation fails with symlink-blocked category code.

### Requirement: Actionable operator guidance
- The system SHALL emit remediation hints for each destructive failure category.

#### Scenario: Permission denied
- GIVEN removal fails due to permissions
- WHEN failure is logged
- THEN output includes category + actionable suggestion.

### Requirement: Runtime failure fallback
- The system SHALL map unknown runtime failures to a runtime-failure category.

#### Scenario: malformed find predicate
- GIVEN `safe_find_delete` receives invalid find arguments
- WHEN find execution fails
- THEN the operation returns runtime-failure category and logs details.
