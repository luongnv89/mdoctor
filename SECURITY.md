# Security Policy

## Supported Versions

Only the **latest release tag** receives security fixes. `install.sh`
and `mdoctor update` (stable channel) both pin installs to the newest
annotated `vX.Y.Z` tag — so "supported" means whatever
`git tag -l 'v*.*.*'` sorts last, currently the v3.x line. Older tags
(including the v1.x and v2.x majors) are unsupported; move to the
latest tag with `mdoctor update`.

| Version | Supported          |
| ------- | ------------------ |
| Latest `vX.Y.Z` release tag (v3.x line) | :white_check_mark: |
| Older release tags (v2.x, v1.x) and untagged commits | :x: |

## Threat Model

In scope for a security report — the privileged and destructive
surfaces an attacker or a bug could turn against the user (the full
defensive model is documented in [docs/SAFETY.md](docs/SAFETY.md)):

- **Destructive deletions** — `mdoctor clean --force` (`cleanup.sh`)
  routes removals through the `lib/safety.sh` validators (allowed
  deletion roots, traversal and symlink checks, the cleanup whitelist).
  A bypass that deletes outside those roots is in scope.
- **Installer privileges** — `install.sh` clones into
  `MDOCTOR_INSTALL_DIR`, can `rm -rf` a corrupt install dir, and writes
  the `/usr/local/bin` symlink (via `sudo` when the directory is
  root-owned). Release tags must be annotated and are signature-checked
  (`MDOCTOR_REQUIRE_TAG_SIGNATURE=true` refuses unverifiable ones).
- **Self-update path** — `mdoctor update` fetches refs and merges
  `--ff-only` into the live install dir. Forged tags, non-annotated
  refs, or a merge landing unexpected code are in scope.
- **Uninstaller** — `uninstall.sh` removes `MDOCTOR_INSTALL_DIR` and
  `MDOCTOR_BIN_LINK` after proving the dir is an mdoctor checkout and
  the link is a symlink; a guard bypass is in scope.
- **Sudo-escalated fix/cleanup targets** — `fixes/` modules and
  `cleanups/apt.sh` run privileged commands (`sudo apt-get …`,
  service restarts); privilege misuse there is in scope.
- **External command surface** — checks and fixes execute tools found
  on `PATH` (`git`, `brew`, `docker`, `apt-get`, …) under
  `mdoctor_timeout` caps. A PATH shim that gains execution through
  mdoctor, or a probe that evades its timeout, is in scope.

Out of scope: issues requiring physical access or an already-root
attacker, cosmetic/output bugs, and test-only PATH stubs that never run
on a user system.

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### How to Report

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email your findings to luongnv89@gmail.com
3. Include detailed steps to reproduce the vulnerability
4. Allow up to 48 hours for an initial response

### What to Include

- Type of vulnerability
- Full paths of affected source files
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce
- Proof-of-concept or exploit code (if possible)
- Impact of the issue

### What to Expect

- Acknowledgment of your report within 48 hours
- Regular updates on our progress
- Credit in the security advisory (if desired)
- Notification when the issue is fixed

## Security Best Practices

When contributing to this project:

- Never commit secrets, API keys, or credentials
- Use environment variables for sensitive configuration
- Follow secure coding practices
- Report any security concerns immediately
