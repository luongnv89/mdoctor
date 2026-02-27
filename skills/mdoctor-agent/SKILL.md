---
name: mdoctor-agent
description: Install, verify, and operate mdoctor on macOS and Debian-based Linux. Use when users ask to set up mdoctor, install dependencies, test branch builds on the current machine, run first health checks, troubleshoot install/runtime issues, or perform safe cleanup/fix workflows with mdoctor commands.
---

# mdoctor Agent

Run reliable mdoctor setup + usage workflows, with dependency handling built in.

## Quick start

From the mdoctor repo root, run:

```bash
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh
```

Useful modes:

```bash
# Preview only
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh --dry-run

# Dev mode: link current checkout (best for branch testing)
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh --method dev --user-bin

# Force local installer behavior (~/.mdoctor clone/update)
bash skills/mdoctor-agent/scripts/install_mdoctor_with_deps.sh --method local
```

## Workflow

### 1) Preflight
- Detect OS (`Darwin` or Debian-family Linux only).
- Validate method (`auto|dev|local|remote`).
- Check required dependencies:
  - `git` for local/remote methods
  - `curl` for remote method
- If dependencies are missing:
  - Linux: install via `sudo apt update && sudo apt install -y ...`
  - macOS: instruct user to run `xcode-select --install` (or Homebrew install)

### 2) Install mdoctor
Choose method by intent:
- `dev`: symlink current repo `./mdoctor` into bin dir (branch-accurate testing)
- `local`: run local `install.sh` (installs under `~/.mdoctor`)
- `remote`: one-line installer from GitHub
- `auto` (default): prefer `dev` when current repo is available, fallback to `local`, then `remote`

Optional flags:
- `--user-bin`: use `~/.local/bin` (avoids sudo in most cases)
- `--repo-root <path>`: override repository root for dev/local modes

### 3) Verify installation
Run smoke checks:

```bash
mdoctor version
mdoctor help
mdoctor info
mdoctor check -m system
```

The installer script forces a safe TERM fallback for non-interactive sessions to reduce `tput` noise during checks.

### 4) First safe usage
Prefer non-destructive commands first:

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
