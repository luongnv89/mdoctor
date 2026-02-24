# Design: task-p6-0-debian-support-plan

## Planning Strategy
1. Keep current macOS behavior unchanged while adding Linux abstractions.
2. Introduce platform adapters before porting modules.
3. Port read-only checks first, cleanup second, fixes last.
4. Add CI matrix coverage (`macOS + Ubuntu`) early.
5. Ship Linux support behind explicit platform detection and clear unsupported messaging.

## Deliverables
- `docs/LINUX_DEBIAN_PLAN.md` with phased roadmap
- `openspec/tasks.md` Phase P6 entries
- archived planning change for traceability
