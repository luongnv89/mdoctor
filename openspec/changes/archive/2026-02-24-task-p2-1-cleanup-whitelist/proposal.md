# Proposal: task-p2-1-cleanup-whitelist

## Why
Users need a way to protect important paths (e.g., models, caches, project artifacts) from cleanup, even when broad cleanup modules run.

## Scope
- In scope:
  - Add whitelist config file support for cleanup safety layer.
  - Skip deletion for whitelisted paths and descendants.
  - Add user guidance in `mdoctor clean --help`.
- Out of scope:
  - Interactive whitelist editor.
  - Advanced glob expression engine.

## Acceptance Criteria
- [x] Whitelist file is auto-created when needed at `~/.config/mdoctor/cleanup_whitelist`.
- [x] `safe_remove` skips whitelisted paths.
- [x] Whitelisting a directory protects its descendants.
- [x] Cleanup still proceeds for non-whitelisted targets.
- [x] `mdoctor clean --help` documents whitelist behavior.

## Risks
- Overbroad whitelist entries may reduce cleanup effectiveness.
  - Mitigation: include clear comments/examples in whitelist file template.
