---
name: mdoctor-agent
description: Install, verify, and operate mdoctor on macOS and Debian-based Linux. Use when users ask to set up mdoctor, install dependencies, run first health checks, troubleshoot install/runtime issues, or perform safe cleanup/fix workflows with mdoctor commands.
---

# mdoctor Agent

Run reliable mdoctor setup + usage workflows, with dependency handling built in.

## Quick start

From the mdoctor repo root, run the bundled installer helper:

```bash
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh
```

Preview only (recommended first):

```bash
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh --dry-run
```

No sudo preferred (installs binary link to `~/.local/bin`):

```bash
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh --user-bin
```

## Workflow

### 1) Preflight
- Detect OS (`Darwin` or Debian-family Linux only).
- Check required dependencies:
  - Required: `git`
  - Required for remote install mode: `curl`
- If dependencies are missing:
  - Linux: install via `sudo apt update && sudo apt install -y ...`
  - macOS: instruct user to run `xcode-select --install` (or Homebrew install)

### 2) Install mdoctor
Choose method:
- `local` (preferred in repo): run local `install.sh`
- `remote`: use one-line installer from GitHub
- `auto` (default): local if available, otherwise remote

### 3) Verify installation
Run smoke checks:

```bash
mdoctor version
mdoctor help
mdoctor info
mdoctor check -m system
```

### 4) First safe usage
For first run, prefer non-destructive commands:

```bash
mdoctor check
mdoctor clean
mdoctor list
```

Only run destructive cleanup with explicit intent:

```bash
mdoctor clean --force
```

### 5) Troubleshooting
- If `mdoctor` is not found: verify symlink target and PATH.
- If `/usr/local/bin` is not writable: rerun with `--user-bin`.
- If Linux distro unsupported: stop and explain Debian-family limitation.
- If `sudo` is unavailable in remote sessions: provide exact commands for user to run locally.

## Command reference

Common operations:

```bash
mdoctor check
mdoctor check --json
mdoctor check -m security
mdoctor clean
mdoctor clean --interactive
mdoctor fix dns
mdoctor fix disk
mdoctor update --check
mdoctor update
```

## Guardrails
- Ask before state-changing operations (`clean --force`, `fix *`, package installs).
- Prefer read-only diagnosis first, then targeted fixes.
- Do not claim support for non-Debian Linux.
