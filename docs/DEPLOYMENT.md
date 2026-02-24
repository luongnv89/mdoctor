# Deployment

## Distribution

mdoctor is distributed via GitHub. Users install it with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/luongnv89/mdoctor/main/install.sh | bash
```

## What the Installer Does

1. Clones the repo to `~/.mdoctor` (shallow clone, `--depth 1`)
2. Makes the main scripts executable
3. Creates a symlink: `/usr/local/bin/mdoctor` -> `~/.mdoctor/mdoctor`
4. Verifies the installation

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

1. Update `MDOCTOR_VERSION` in the `mdoctor` script
2. Update `docs/CHANGELOG.md`
3. Commit and push to `main`
4. Create a GitHub release with a tag (e.g., `v1.1.0`)

Users on next update (`install.sh` re-run) will automatically get the latest version.
