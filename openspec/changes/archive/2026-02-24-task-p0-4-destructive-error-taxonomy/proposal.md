# Proposal: task-p0-4-destructive-error-taxonomy

## Why
Safety primitives exist, but failure reporting is still coarse. We need standardized failure categories and actionable operator guidance to speed up triage.

## Scope
- In scope:
  - Define explicit destructive-operation error taxonomy.
  - Map low-level failures to taxonomy codes (invalid target, protected target, symlink blocked, permission denied, SIP/read-only, runtime failure).
  - Emit actionable CLI log hints per category.
- Out of scope:
  - New command surface for querying errors.
  - Whitelist/policy tuning (P2).

## Acceptance Criteria
- [x] Taxonomy constants are centralized in `lib/safety.sh`.
- [x] `safe_remove` maps common deletion failures to taxonomy codes.
- [x] Validation failures return taxonomy codes consistently.
- [x] Logs include clear category + remediation hint.
- [x] Smoke checks cover representative failure categories.

## Risks
- Exact SIP detection can be ambiguous (`Operation not permitted` may overlap with permissions).
  - Mitigation: classify read-only/SIP-like signals together and provide conservative remediation hints.
