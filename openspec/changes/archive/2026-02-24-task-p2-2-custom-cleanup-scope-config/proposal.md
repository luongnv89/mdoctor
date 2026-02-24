# Proposal: task-p2-2-custom-cleanup-scope-config

## Why
`dev_caches` currently scans stale `node_modules` in hardcoded directories. Users need a configurable include/exclude scope to avoid scanning sensitive or irrelevant paths and to target their actual workspace layout.

## Scope
- In scope:
  - Add cleanup scope config file with include/exclude rules.
  - Use scope config for stale `node_modules` scan in `cleanups/dev_caches.sh`.
  - Auto-create config template.
  - Document scope config in clean help and environment variables.
- Out of scope:
  - Interactive scope editor.
  - Full migration of every cleanup module to scope config.

## Acceptance Criteria
- [x] Scope config file is auto-created at `~/.config/mdoctor/cleanup_scope.conf`.
- [x] Include paths can override default stale-node_modules scan paths.
- [x] Exclude glob patterns skip matched paths from stale-node_modules cleanup.
- [x] Non-configured behavior remains equivalent to previous defaults.
- [x] Help text documents scope config.

## Risks
- Misconfigured includes may skip useful cleanup.
  - Mitigation: clear template comments and fallback defaults when no includes are set.
