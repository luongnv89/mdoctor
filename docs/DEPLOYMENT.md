# Deployment

## Distribution

mdoctor is distributed via GitHub and supports macOS and Debian-based Linux (Debian, Ubuntu, Pop!_OS, Linux Mint, Raspbian, Elementary OS, Zorin, Kali). Users install it with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash
```

## What the Installer Does

1. Detects the platform (macOS or Debian-based Linux via `uname -s` and `/etc/os-release`)
2. Clones the repo to `~/.mdoctor` (shallow clone, `--depth 1`)
3. Makes the main scripts executable
4. Creates a symlink: `/usr/local/bin/mdoctor` -> `~/.mdoctor/mdoctor`
5. Verifies the installation

> **Linux prerequisite:** `git` must be installed (`sudo apt install git`). Non-Debian distros are rejected with an informative error message.

## Updating

Preferred path:

```bash
mdoctor update
```

Check-only mode:

```bash
mdoctor update --check
```

Fallback path (still supported): re-run installer. The installer detects the existing directory and runs `git pull --ff-only`.

## Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/uninstall.sh | bash
```

This removes the symlink and `~/.mdoctor` directory.

## Releasing a New Version

`MDOCTOR_VERSION` in the `mdoctor` script is the single source of truth.
Every other version site must match it — enforced by
`./scripts/check_version.sh` (and by the release workflow, which fails
the build otherwise):

1. Update `MDOCTOR_VERSION` in the `mdoctor` script
2. Update `docs/CHANGELOG.md` (add `## [X]`), `RELEASE_NOTES.md` (title
   `## vX` plus the `...vX` changelog link), and the worked example
   below so all three name the same version
3. Run `./scripts/check_version.sh` locally — it must exit 0
4. Commit and push to `main`
5. Create/push release tag (e.g., `v3.0.0`) — the `Release` workflow
   (`push: tags: v*.*.*`) re-runs the agreement check against the tag
   and creates the GitHub release automatically, with no further file
   edits

Example (`gh` CLI):

```bash
git tag -a v3.0.0 -m "mdoctor v3.0.0"
git push origin v3.0.0

# The Release workflow then creates the release titled "mdoctor v3.0.0"
# with docs/CHANGELOG.md as the notes. Manual equivalent (fallback only):
gh release create v3.0.0 \
  --repo luongnv89/mdoctor \
  --title "mdoctor v3.0.0" \
  --notes-file docs/CHANGELOG.md \
  --draft

# publish draft when ready
gh release edit v3.0.0 --repo luongnv89/mdoctor --draft=false
```

Users can then upgrade via `mdoctor update` (preferred) or by rerunning `install.sh`.
