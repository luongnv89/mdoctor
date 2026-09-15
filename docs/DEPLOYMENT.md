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

## Installer Environment Variables

`install.sh` and `uninstall.sh` read no config file — every knob is an
environment variable. This is the complete surface (the same list
`install.sh --help` prints, plus the uninstaller-only and policy
variables):

| Variable | Consumed by | Default | Effect |
|----------|-------------|---------|--------|
| `MDOCTOR_REPO_URL` | `install.sh` | `https://github.com/luongnv89/mdoctor.git` | Git remote cloned into the install dir |
| `MDOCTOR_INSTALL_DIR` | `install.sh`, `uninstall.sh` | `~/.mdoctor` | Install location; also the directory the uninstaller removes |
| `MDOCTOR_BIN_DIR` | `install.sh` | `/usr/local/bin` | Directory holding the symlink — validated: allowlisted, or an existing directory ending in `/bin` |
| `MDOCTOR_BINARY_NAME` | `install.sh` | `mdoctor` | Symlink name inside the bin dir — a plain filename (`A-Z a-z 0-9 _ . -`), never a path |
| `MDOCTOR_CHANNEL` | `install.sh`, `mdoctor update` | `stable` | `stable` = newest verified `vX.Y.Z` tag; `main` = branch head |
| `MDOCTOR_REQUIRE_TAG_SIGNATURE` | `install.sh`, `mdoctor update` | `false` | `true` refuses release tags without a verifiable signature |
| `MDOCTOR_ASSUME_YES` | `install.sh`, `uninstall.sh` | `false` | `true` skips the interactive confirmation gates (custom symlink prompt, uninstall prompt) |
| `MDOCTOR_BIN_LINK` | `uninstall.sh` | `/usr/local/bin/mdoctor` | Full path of the symlink the uninstaller removes |
| `MDOCTOR_SKIP_PLATFORM_CHECK` | `install.sh` | `false` | `true` bypasses the macOS/Debian-family gate — a CI escape hatch, not a supported-install flag |
| `MDOCTOR_NO_COLOR` | `install.sh`, `uninstall.sh` | unset | Any non-empty value disables colored output (same contract as `NO_COLOR`) |

Two follow-on rules matter for custom installs:

- Setting `MDOCTOR_BIN_DIR` or `MDOCTOR_BINARY_NAME` triggers a
  confirmation gate — the installer prints the exact `ln -s` command and
  needs an explicit `y` (or `MDOCTOR_ASSUME_YES=true` on a non-tty)
  before writing the symlink.
- The uninstaller removes exactly `MDOCTOR_INSTALL_DIR` and
  `MDOCTOR_BIN_LINK` — nothing else. A custom install must re-declare
  both at uninstall time or the defaults silently remove nothing (see
  [Uninstalling](#uninstalling)). User config under
  `~/.config/mdoctor` (whitelist, scope, history) is always retained.

## Updating

Preferred path:

```bash
mdoctor update
```

Check-only mode:

```bash
mdoctor update --check
```

Channel selection (`stable` is the default; `main` tracks the branch
head — `MDOCTOR_CHANNEL` is the environment form):

```bash
mdoctor update --channel main
```

Fallback path (still supported): re-run installer. The installer detects the existing directory and runs `git pull --ff-only`.

## Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/uninstall.sh | bash
```

This removes the symlink and `~/.mdoctor` directory.

If the install used `MDOCTOR_INSTALL_DIR`, `MDOCTOR_BIN_DIR` or
`MDOCTOR_BINARY_NAME` overrides, pass the matching uninstaller
variables — the defaults would remove nothing:

```bash
MDOCTOR_INSTALL_DIR=/opt/mdoctor \
MDOCTOR_BIN_LINK="${HOME}/.local/bin/mdoctor" \
  ./uninstall.sh
```

(`MDOCTOR_BIN_LINK` is the full symlink path — the uninstall-side
spelling of `MDOCTOR_BIN_DIR`/`MDOCTOR_BINARY_NAME`. See the
[Installer Environment Variables](#installer-environment-variables)
table.)

## Releasing a New Version

`MDOCTOR_VERSION` in the `mdoctor` script is the single source of truth
for the version number, and `docs/CHANGELOG.md` is the single
authoritative changelog — the file the `Release` workflow feeds to
`gh release create --notes-file` (Keep a Changelog format, full history
back to v1.0.0).

Decision (Task 13.6): the root `RELEASE_NOTES.md` — formerly a second,
version-titled highlights document — is reduced to a pointer at
`docs/CHANGELOG.md` and the GitHub Releases page. It carries no
per-release content and needs no release-time edits, so the stale
per-release statistics it used to hand-maintain no longer exist.

### Files a release touches

| File | Release-time edit | Derived / verified by |
| --- | --- | --- |
| `mdoctor` | Bump `MDOCTOR_VERSION` (manual — the one literal everything else follows) | Source of truth for `mdoctor version`, `lib/json.sh`, and every check below |
| `docs/CHANGELOG.md` | Move `[Unreleased]` items under a new `## [X.Y.Z] - YYYY-MM-DD` heading (manual) | `scripts/check_version.sh` requires `## [X.Y.Z]` |
| `docs/DEPLOYMENT.md` | Retarget the worked example below to `vX.Y.Z` (manual) | `scripts/check_version.sh` requires `git tag -a vX.Y.Z` |
| `lib/json.sh` | None — the version flows from `MDOCTOR_VERSION` (derived) | `scripts/check_version.sh` forbids a `MDOCTOR_VERSION:-<digit>` literal fallback |
| `RELEASE_NOTES.md` | None — pointer only (Task 13.6) | `tests/test_changelog_authority.bats` forbids `## v` headings, stats and compare links |
| `README.md`, `docs/GUIDEBOOK.md`, `docs/ARCHITECTURE.md` | None per release — per-platform module/step counts change only when `lib/registry.sh` or `CLEANUP_STEPS` in `cleanup.sh` changes | `tests/test_doc_counts.bats` derives every count claim from the registry and `cleanup.sh` |
| release tag `vX.Y.Z` | `git tag -a vX.Y.Z` (manual) | Release workflow runs `check_version.sh "$tag"` — tag must equal `v${MDOCTOR_VERSION}` |

### Steps

1. Update `MDOCTOR_VERSION` in the `mdoctor` script
2. Update `docs/CHANGELOG.md` (move the `[Unreleased]` items under
   `## [X.Y.Z] - YYYY-MM-DD`) and the worked example below so both name
   the same version — no other file carries the version
3. Run `./scripts/check_version.sh` locally — it must exit 0
4. Commit and push to `main`
5. Create/push release tag (e.g., `v3.1.0`) — the `Release` workflow
   (`push: tags: v*.*.*`) re-runs the agreement check against the tag
   and creates the GitHub release from `docs/CHANGELOG.md`
   automatically, with no further file edits

Example (`gh` CLI):

```bash
git tag -a v3.1.0 -m "mdoctor v3.1.0"
git push origin v3.1.0

# The Release workflow then creates the release titled "mdoctor v3.1.0"
# with docs/CHANGELOG.md as the notes. Manual equivalent (fallback only):
gh release create v3.1.0 \
  --repo luongnv89/mdoctor \
  --title "mdoctor v3.1.0" \
  --notes-file docs/CHANGELOG.md \
  --draft

# publish draft when ready
gh release edit v3.1.0 --repo luongnv89/mdoctor --draft=false
```

Users can then upgrade via `mdoctor update` (preferred) or by rerunning `install.sh`.
