#!/usr/bin/env bats
#
# test_safety_doc_defaults.bats — issue #118 (task 13.5)
#
# docs/SAFETY.md documents the cleanup whitelist and the dev_caches
# cleanup-scope defaults; this file asserts the documentation matches
# the code it describes, so the two cannot drift again:
#
# 1. Scope defaults — the empty-file defaults are derived live from
#    _mdoctor_scope_default_dirs() (lib/cleanup_scope.sh), the
#    `-maxdepth N` bound in cleanups/dev_caches.sh, and the
#    DAYS_OLD_NODE_MODULES default. SAFETY.md must name every one of
#    them, and README's Configuration section must name the variable.
# 2. Whitelist rules — SAFETY.md states the tilde-expansion rule in the
#    generated template's own wording (leading ~ only, the anchor the
#    code applies) and the trailing-glob rule covers the base path the
#    way is_whitelisted_cleanup_path() implements it.
#
# Hermetic: repository files are only read; the scope function runs in
# a subshell under a fixture HOME and performs no I/O itself.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
SAFETY="$ROOT_DIR/docs/SAFETY.md"
README="$ROOT_DIR/README.md"

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-safetydoc.$(fixture_run_id).XXXXXX")"
  export TEST_TMP
  fixture_trap_cleanup "$TEST_TMP"
  TEST_HOME="$TEST_TMP/home"
  mkdir -p "$TEST_HOME"
  export TEST_HOME
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

# _scope_section / _whitelist_section — the SAFETY.md sections under
# test, sliced by their markdown headings.
_scope_section() {
  sed -n '/^### Cleanup scope/,/^## /p' "$SAFETY"
}

_whitelist_section() {
  sed -n '/^### Cleanup whitelist/,/^### Cleanup scope/p' "$SAFETY"
}

# _code_roots — the default scan roots exactly as the code prints them,
# rendered in the ~/… spelling the doc uses. Runs under the fixture
# HOME; _mdoctor_scope_default_dirs only interpolates $HOME into
# printf output and touches nothing on disk.
_code_roots() {
  (
    export HOME="$TEST_HOME"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/cleanup_scope.sh"
    _mdoctor_scope_default_dirs
  ) | sed "s|^${TEST_HOME}/|~/|" | sort
}

# _doc_roots — the backtick-quoted `~/name` tokens in the scope
# section's defaults list. Bare example values (INCLUDE_PATH=~/x) carry
# no backticks and never match.
_doc_roots() {
  _scope_section | grep -oE '`~/[A-Za-z0-9_]+`' | tr -d '`' | sort
}

@test "SAFETY.md scope defaults list exactly the roots the code scans" {
  local code_roots doc_roots
  code_roots="$(_code_roots)"
  doc_roots="$(_doc_roots)"
  [ -n "$code_roots" ] || fail "could not derive roots from _mdoctor_scope_default_dirs"
  [ -n "$doc_roots" ] || fail "no `~/dir` default roots found in SAFETY.md scope section"
  [ "$doc_roots" = "$code_roots" ] || {
    printf 'code roots:\n%s\ndoc roots:\n%s\n' "$code_roots" "$doc_roots" >&2
    fail "documented default scan roots diverge from lib/cleanup_scope.sh"
  }
}

@test "SAFETY.md states the code's scan depth and staleness variable" {
  local code_depth code_default
  code_depth="$(grep -oE '\-maxdepth [0-9]+' "$ROOT_DIR/cleanups/dev_caches.sh" | head -n 1 | grep -oE '[0-9]+')"
  [ -n "$code_depth" ] || fail "no -maxdepth bound found in dev_caches.sh"
  _scope_section | grep -qE "maxdepth ${code_depth}|depth of ${code_depth}([^0-9]|$)" \
    || fail "scope section does not state the code's depth bound (${code_depth})"

  code_default="$(sed -n 's/.*DAYS_OLD_NODE_MODULES="[^"]*:-\([0-9][0-9]*\).*/\1/p' "$ROOT_DIR/cleanups/dev_caches.sh" | head -n 1)"
  [ -n "$code_default" ] || fail "no DAYS_OLD_NODE_MODULES default found in dev_caches.sh"
  _scope_section | grep -q 'DAYS_OLD_NODE_MODULES' \
    || fail "scope section does not name DAYS_OLD_NODE_MODULES"
  _scope_section | grep -qE "default: *${code_default}([^0-9]|$)" \
    || fail "documented DAYS_OLD_NODE_MODULES default diverges from dev_caches.sh (${code_default})"
}

@test "README configuration section names the staleness variable" {
  sed -n '/^## Configuration/,/^## /p' "$README" | grep -q 'DAYS_OLD_NODE_MODULES' \
    || fail "README Configuration section does not name DAYS_OLD_NODE_MODULES"
}

@test "whitelist tilde rule mirrors the generated template and is leading-only" {
  # The code anchors expansion: ${line/#\~/$HOME} rewrites a leading
  # tilde only — a mid-path tilde stays literal.
  grep -qF 'line="${line/#\~/$HOME}"' "$ROOT_DIR/lib/safety.sh" \
    || fail "lib/safety.sh no longer anchors tilde expansion at line start"
  # The generated template's own wording is what the doc must mirror.
  grep -qF '~ is expanded to your home directory' "$ROOT_DIR/lib/safety.sh" \
    || fail "generated whitelist template lost its tilde-expansion note"
  # Issue #230: the template itself must state the leading-only rule —
  # the drift this file guards against ran template-vs-doc too.
  grep -qF 'leading ~ is expanded to your home directory' "$ROOT_DIR/lib/safety.sh" \
    || fail "generated whitelist template does not state tilde expansion is leading-only"
  _whitelist_section | grep -q 'is expanded to your home directory' \
    || fail "SAFETY.md whitelist rules do not mirror the template's tilde wording"
  _whitelist_section | grep -qi 'leading' \
    || fail "SAFETY.md whitelist rules do not state expansion is leading-tilde only"
}

@test "trailing-glob rule covers the base path like the implementation" {
  # is_whitelisted_cleanup_path matches a /* entry when the candidate
  # equals the base itself or sits under it.
  grep -qF 'if [ "$path" = "$base" ] || [[ "$path" == "$base/"* ]]' "$ROOT_DIR/lib/safety.sh" \
    || fail "trailing-glob implementation no longer matches the base path"
  # Issue #230: the generated template must carry the same base-path rule.
  local template_glob
  template_glob="$(grep -F 'trailing /*' "$ROOT_DIR/lib/safety.sh" || true)"
  [ -n "$template_glob" ] || fail "generated whitelist template lost its /* rule"
  printf '%s\n' "$template_glob" | grep -qi 'base path' \
    || fail "generated template /* rule does not name the base path"
  printf '%s\n' "$template_glob" | grep -qi 'itself' \
    || fail "generated template /* rule does not protect the base path itself"
  local glob_line
  glob_line="$(_whitelist_section | grep -F '/*' | grep -i 'protect' || true)"
  [ -n "$glob_line" ] || fail "no /* protection rule found in SAFETY.md whitelist rules"
  printf '%s\n' "$glob_line" | grep -qi 'base path' \
    || fail "/* rule does not name the base path"
  printf '%s\n' "$glob_line" | grep -qiE 'itself|as well' \
    || fail "/* rule does not state the base path itself is protected"
}
