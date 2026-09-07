#!/usr/bin/env bash
# Task 4.3: temp files come from mktemp under a per-user 0700 dir — a
# stale file planted at an old predictable path is never touched.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"
source "$ROOT_DIR/lib/common.sh"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

cd "$ROOT_DIR"

# Helpers land under a 0700 per-user dir.
dir="$(mdoctor_tmpdir)"
[ -d "$dir" ] || fail "Expected tmpdir to exist"
[ "$(stat -c %a "$dir")" = "700" ] || fail "Expected 0700 on tmpdir"
f="$(mdoctor_mktemp_file probe)"
[ -f "$f" ] || fail "Expected mktemp file to exist"
rm -f "$f"

# A hostile stale file at the old predictable path is unaffected by the
# module that used to truncate it.
printf 'HOSTILE' > /tmp/docker_info.log
trap 'rm -rf "$TMPD" /tmp/docker_info.log' EXIT
./mdoctor check -m devtools >/dev/null 2>&1 || true
[ "$(cat /tmp/docker_info.log 2>/dev/null)" = "HOSTILE" ] || fail "Planted /tmp/docker_info.log was touched"

pass "mktemp temp files under a 0700 per-user dir"
