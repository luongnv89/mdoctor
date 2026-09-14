#!/usr/bin/env bats
#
# test_changelog_authority.bats — issue #119 (task 13.6)
#
# One changelog is authoritative and the release checklist is complete:
#
# 1. docs/DEPLOYMENT.md declares docs/CHANGELOG.md the authoritative
#    changelog and records that RELEASE_NOTES.md was reduced to a
#    pointer — and the release workflow really does consume
#    docs/CHANGELOG.md (the --notes-file argument in release.yml), so
#    the declaration matches the pipeline rather than just prose.
#
# 2. RELEASE_NOTES.md is a pointer: it links docs/CHANGELOG.md and the
#    GitHub Releases page and carries no per-release material — no
#    "## vX" version heading, no "### Stats" block, no "...vX" compare
#    link (exactly the literals check_version.sh used to pin and the
#    stats that went stale after v3.0.0).
#
# 3. scripts/check_version.sh is consistent with the decision: it still
#    pins docs/CHANGELOG.md's "## [X]" heading, DEPLOYMENT's worked
#    example and the lib/json.sh no-fallback rule to MDOCTOR_VERSION,
#    and it no longer greps RELEASE_NOTES.md.
#
# 4. docs/LINUX_DEBIAN_PLAN.md is stamped shipped (v3.0.0) with a done
#    marker on every P6.x phase heading, and the README index entries
#    for the plan and the pointer no longer read as a live roadmap /
#    highlights document.
#
# Read-only: asserts on repository files, touches nothing.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
DEPLOYMENT="$ROOT_DIR/docs/DEPLOYMENT.md"
RELEASE_NOTES="$ROOT_DIR/RELEASE_NOTES.md"
CHANGELOG="$ROOT_DIR/docs/CHANGELOG.md"
PLAN="$ROOT_DIR/docs/LINUX_DEBIAN_PLAN.md"
README="$ROOT_DIR/README.md"
CHECK_VERSION="$ROOT_DIR/scripts/check_version.sh"
RELEASE_YML="$ROOT_DIR/.github/workflows/release.yml"

# _release_section — the "Releasing a New Version" section of
# DEPLOYMENT.md (it is the last section, so it runs to EOF).
_release_section() {
  sed -n '/^## Releasing a New Version/,$p' "$DEPLOYMENT"
}

# _index_entry BASENAME — the README documentation-index line linking
# BASENAME (e.g. docs/LINUX_DEBIAN_PLAN.md).
_index_entry() {
  grep -F "]($1)" "$README"
}

@test "DEPLOYMENT declares docs/CHANGELOG.md the authoritative changelog" {
  # The declaration sentence may wrap; join lines before matching so the
  # file name and the phrase are compared in one string.
  _release_section | tr -d '\n' \
    | grep -q 'docs/CHANGELOG.md` is the single[[:space:]]*authoritative changelog' \
    || fail "DEPLOYMENT.md does not declare docs/CHANGELOG.md the single authoritative changelog"
  # The declaration must match the pipeline: the release workflow feeds
  # docs/CHANGELOG.md to gh release create, never RELEASE_NOTES.md.
  grep -q -- '--notes-file docs/CHANGELOG.md' "$RELEASE_YML" \
    || fail "release.yml does not consume docs/CHANGELOG.md as release notes"
  if grep -q 'notes-file.*RELEASE_NOTES' "$RELEASE_YML"; then
    fail "release.yml still sources release notes from RELEASE_NOTES.md"
  fi
}

@test "DEPLOYMENT records the pointer decision for RELEASE_NOTES.md" {
  _release_section | grep -qF 'RELEASE_NOTES.md' \
    || fail "release checklist does not mention RELEASE_NOTES.md"
  _release_section | grep -qi 'pointer' \
    || fail "checklist does not record that RELEASE_NOTES.md is a pointer"
}

@test "RELEASE_NOTES.md is a pointer with no per-release material" {
  grep -qF 'docs/CHANGELOG.md' "$RELEASE_NOTES" \
    || fail "pointer does not link the authoritative changelog"
  grep -q 'github.com/luongnv89/mdoctor/releases' "$RELEASE_NOTES" \
    || fail "pointer does not link the GitHub Releases page"
  if grep -qE '^## +v[0-9]' "$RELEASE_NOTES"; then
    fail "RELEASE_NOTES.md still carries a '## vX' version heading"
  fi
  if grep -qF '### Stats' "$RELEASE_NOTES"; then
    fail "RELEASE_NOTES.md still carries a per-release Stats block"
  fi
  if grep -qF '...v' "$RELEASE_NOTES"; then
    fail "RELEASE_NOTES.md still carries a '...vX' compare link"
  fi
  # Hand-maintained release statistics were the drift source (the old
  # "6 regression tests" line); none may survive in the pointer.
  if grep -qE '[0-9]+ (regression tests|CI jobs|files changed)' "$RELEASE_NOTES"; then
    fail "RELEASE_NOTES.md still carries hand-maintained release statistics"
  fi
}

@test "check_version.sh validates the changelog, never the pointer" {
  # No grep may target RELEASE_NOTES.md (a comment may still name it).
  if grep -n 'grep .*RELEASE_NOTES' "$CHECK_VERSION" >/dev/null; then
    fail "check_version.sh still greps RELEASE_NOTES.md"
  fi
  grep -qF '## [$VERSION]' "$CHECK_VERSION" \
    || fail "check_version.sh lost the docs/CHANGELOG.md '## [X]' check"
  grep -qF 'git tag -a v$VERSION' "$CHECK_VERSION" \
    || fail "check_version.sh lost the DEPLOYMENT worked-example check"
  grep -qF 'MDOCTOR_VERSION:-[0-9]' "$CHECK_VERSION" \
    || fail "check_version.sh lost the lib/json.sh no-literal-fallback check"
  # And it must pass on the current tree (the constant, changelog and
  # worked example all agree on the shipped version).
  "$CHECK_VERSION" >/dev/null 2>&1 \
    || fail "check_version.sh does not exit 0 on the current tree"
}

@test "release checklist enumerates every file a release touches" {
  local f missing=""
  for f in \
    'mdoctor' 'docs/CHANGELOG.md' 'docs/DEPLOYMENT.md' 'RELEASE_NOTES.md' \
    'lib/json.sh' 'README.md' 'docs/GUIDEBOOK.md' 'docs/ARCHITECTURE.md' \
    'check_version.sh' 'test_doc_counts.bats'; do
    _release_section | grep -qF "$f" || missing="${missing}${f} "
  done
  [ -z "$missing" ] || fail "release checklist does not enumerate: $missing"
}

@test "authoritative changelog tracks MDOCTOR_VERSION and lists diagnose" {
  local version
  version="$(sed -n 's/^MDOCTOR_VERSION="\(.*\)"/\1/p' "$ROOT_DIR/mdoctor")"
  [ -n "$version" ] || fail "MDOCTOR_VERSION constant not found in mdoctor"
  grep -qF "## [$version]" "$CHANGELOG" \
    || fail "docs/CHANGELOG.md lacks a '## [$version]' entry"
  grep -qi 'diagnose' "$CHANGELOG" \
    || fail "docs/CHANGELOG.md lacks an entry for mdoctor diagnose"
}

@test "LINUX_DEBIAN_PLAN.md is stamped shipped with per-phase markers" {
  grep -qE '^Status:.*[Ss]hipped' "$PLAN" \
    || fail "LINUX_DEBIAN_PLAN.md Status line is not stamped shipped"
  grep -q 'v3.0.0' "$PLAN" \
    || fail "shipped status does not name v3.0.0"
  local phases marked
  phases="$(grep -c '^### P6\.' "$PLAN")"
  marked="$(grep -cE '^### P6\.[0-9].*done' "$PLAN")"
  [ "$phases" -ge 7 ] \
    || fail "expected >=7 phase headings in LINUX_DEBIAN_PLAN.md, found $phases"
  [ "$marked" -eq "$phases" ] \
    || fail "only $marked of $phases phase headings carry a done marker"
}

@test "README index entries reflect the shipped plan and the pointer" {
  local line
  line="$(_index_entry 'docs/LINUX_DEBIAN_PLAN.md')"
  [ -n "$line" ] || fail "LINUX_DEBIAN_PLAN.md missing from the README index"
  printf '%s\n' "$line" | grep -qi 'shipped\|completed' \
    || fail "plan index entry still reads as a live roadmap: $line"
  printf '%s\n' "$line" | grep -q 'v3.0.0' \
    || fail "plan index entry does not name the shipping version: $line"

  line="$(_index_entry 'RELEASE_NOTES.md')"
  [ -n "$line" ] || fail "RELEASE_NOTES.md missing from the README index"
  printf '%s\n' "$line" | grep -qi 'pointer' \
    || fail "release-notes index entry does not mark it a pointer: $line"
}
