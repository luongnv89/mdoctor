#!/usr/bin/env bash
# scripts/check_version.sh — single source of truth version check (Task 5.4).
#
# MDOCTOR_VERSION in the `mdoctor` script is the single source of truth.
# Every other version site must match it or this check fails:
#   1. `mdoctor` constant itself (MDOCTOR_VERSION="X")
#   2. no literal fallback in lib/json.sh (unset emits null, never a number)
#   3. docs/CHANGELOG.md entry (## [X])
#   4. RELEASE_NOTES.md title (## vX)
#   5. RELEASE_NOTES.md changelog link (...vX)
#   6. docs/DEPLOYMENT.md worked example (git tag -a vX)
#
# Usage:
#   ./scripts/check_version.sh [EXPECTED_TAG]
# With EXPECTED_TAG (e.g. v3.0.0, from the release workflow's tag push),
# also asserts the tag equals "v${VERSION}".
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

failures=0
fail() {
  echo "check_version FAIL: $1"
  failures=$((failures + 1))
}

VERSION="$(sed -n 's/^MDOCTOR_VERSION="\(.*\)"/\1/p' mdoctor)"
if [ -z "$VERSION" ]; then
  echo "check_version FAIL: MDOCTOR_VERSION constant not found in mdoctor script."
  exit 1
fi
echo "check_version: constant MDOCTOR_VERSION=$VERSION"

# Optional tag agreement (release workflow passes github.ref_name).
if [ "${1:-}" != "" ]; then
  if [ "$1" != "v$VERSION" ]; then
    fail "tag $1 disagrees with constant v$VERSION."
  else
    echo "check_version: tag $1 matches constant."
  fi
fi

# 2. No literal fallback in lib/json.sh — an unset variable must emit
# null, never a fabricated number.
if grep -qE 'MDOCTOR_VERSION:-[0-9]' lib/json.sh 2>/dev/null; then
  fail "lib/json.sh carries a literal version fallback (MDOCTOR_VERSION:-<digit>)."
else
  echo "check_version: lib/json.sh has no literal fallback."
fi

# 3. Changelog entry.
if grep -qF "## [$VERSION]" docs/CHANGELOG.md 2>/dev/null; then
  echo "check_version: docs/CHANGELOG.md has ## [$VERSION]."
else
  fail "docs/CHANGELOG.md lacks entry '## [$VERSION]'."
fi

# 4. Release-notes title.
if grep -qF "## v$VERSION" RELEASE_NOTES.md 2>/dev/null; then
  echo "check_version: RELEASE_NOTES.md has title '## v$VERSION'."
else
  fail "RELEASE_NOTES.md lacks title '## v$VERSION'."
fi

# 5. Release-notes changelog link.
if grep -qF "...v$VERSION" RELEASE_NOTES.md 2>/dev/null; then
  echo "check_version: RELEASE_NOTES.md changelog link ends at v$VERSION."
else
  fail "RELEASE_NOTES.md lacks changelog link ending '...v$VERSION'."
fi

# 6. Deployment worked example.
if grep -qF "git tag -a v$VERSION" docs/DEPLOYMENT.md 2>/dev/null; then
  echo "check_version: docs/DEPLOYMENT.md example tags v$VERSION."
else
  fail "docs/DEPLOYMENT.md lacks worked example 'git tag -a v$VERSION'."
fi

if [ "$failures" -gt 0 ]; then
  echo "check_version: $failures site(s) disagree with MDOCTOR_VERSION=$VERSION."
  exit 1
fi

echo "check_version: OK (all sites agree on $VERSION)."
