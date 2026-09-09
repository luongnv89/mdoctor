#!/usr/bin/env bats
#
# test_json_output.bats
# Issue #90: `mdoctor check --json` must emit a populated `checks` array
# (wired through the status helpers), and `json_escape` must cover all of
# U+0000–U+001F per RFC 8259 §7 while escaping risk/status like their
# siblings.
#
# Hermetic by construction: fixed fixture inputs only (a message carrying
# a form feed and a raw ANSI escape, synthetic module metadata), sandboxed
# HOME under the shared fixture root. No live-host health is asserted
# anywhere in this file. Bash 3.2 compatible (plain `[ ]` tests, indexed
# arrays and while loops only, octal $'' escapes) so every test runs in
# the bash:3.2 container job.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TEST_TMP
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-jsonout.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

setup() {
  export TEST_TMP
  local base="$TEST_TMP/$BATS_TEST_NUMBER"
  mkdir -p "$base/home"
  export HOME="$base/home"
  export TEST_BASE="$base"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/json.sh"
  STEP_CURRENT=0
  STEP_TOTAL=1
  WARN_COUNT=0
  FAIL_COUNT=0
  ACTIONS=()
  REPORT_MD=""
  JSON_ENABLED=true
  init_colors
}

@test "json escapes form feed and ANSI escape; document parses as valid JSON" {
  # issue #90: a message carrying a form feed and a raw ANSI escape must
  # still serialize to valid JSON (RFC 8259 §7 escapes all U+0000–U+001F).
  local msg="load high"$'\f'"peak"$'\033'"[1m spike"
  local esc
  esc="$(json_escape "$msg")"
  printf '%s' "$esc" >"$TEST_BASE/escaped.txt"
  assert_contains "$TEST_BASE/escaped.txt" "u001b"
  # No raw control byte may survive in the escaped string.
  assert_not_contains "$TEST_BASE/escaped.txt" "$(printf '\033')"
  assert_not_contains "$TEST_BASE/escaped.txt" "$(printf '\f')"
  json_set_context "disk" "System" "SAFE"
  json_add_check "disk" "System" "SAFE" "warn" "$msg"
  json_add_action "free space soon"
  json_build_output 80 "Good" 1 0 >"$TEST_BASE/doc.json"
  [ -s "$TEST_BASE/doc.json" ] || fail "json_build_output emitted an empty document"
  if command -v python3 >/dev/null 2>&1; then
    MDOCTOR_TEST_MSG="$msg" python3 - "$TEST_BASE/doc.json" <<'PYEOF' || fail "JSON did not parse or message did not round-trip"
import json, os, sys
with open(sys.argv[1]) as f:
    doc = json.load(f)  # malformed JSON raises -> test fails
assert isinstance(doc["checks"], list) and len(doc["checks"]) == 1, "checks must hold one entry"
assert doc["checks"][0]["message"] == os.environ["MDOCTOR_TEST_MSG"], "message must round-trip byte-identical"
assert doc["checks"][0]["module"] == "disk", "module must survive escaping"
assert isinstance(doc["actions"], list) and len(doc["actions"]) == 1, "actions must hold one entry"
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    jq empty "$TEST_BASE/doc.json" >/dev/null 2>&1 || fail "jq could not parse the JSON document"
  else
    skip "no JSON parser available (need python3 or jq)"
  fi
}

@test "json_add_check escapes risk and status like its siblings" {
  # issue #90: risk/status were interpolated raw while module/category/
  # message were escaped — every field must round-trip byte-identical.
  local mod='disk"x'
  local cat='Sys\tem'
  local risk='M"ED'
  local status="wa$(printf '\n')rn"
  local msg='plain'
  json_add_check "$mod" "$cat" "$risk" "$status" "$msg"
  json_build_output 100 "Excellent" 0 0 >"$TEST_BASE/fields.json"
  [ -s "$TEST_BASE/fields.json" ] || fail "json_build_output emitted an empty document"
  if command -v python3 >/dev/null 2>&1; then
    MDOCTOR_T_MOD="$mod" MDOCTOR_T_CAT="$cat" MDOCTOR_T_RISK="$risk" \
      MDOCTOR_T_STATUS="$status" MDOCTOR_T_MSG="$msg" \
      python3 - "$TEST_BASE/fields.json" <<'PYEOF' || fail "risk/status did not round-trip"
import json, os, sys
with open(sys.argv[1]) as f:
    doc = json.load(f)
entry = doc["checks"][0]
assert entry["module"] == os.environ["MDOCTOR_T_MOD"], "module mismatch: %r" % entry["module"]
assert entry["category"] == os.environ["MDOCTOR_T_CAT"], "category mismatch: %r" % entry["category"]
assert entry["risk"] == os.environ["MDOCTOR_T_RISK"], "risk mismatch: %r" % entry["risk"]
assert entry["status"] == os.environ["MDOCTOR_T_STATUS"], "status mismatch: %r" % entry["status"]
assert entry["message"] == os.environ["MDOCTOR_T_MSG"], "message mismatch: %r" % entry["message"]
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    jq empty "$TEST_BASE/fields.json" >/dev/null 2>&1 || fail "jq could not parse the JSON document"
  else
    skip "no JSON parser available (need python3 or jq)"
  fi
}

@test "status helpers populate the checks array when JSON is enabled" {
  # issue #90: json_add_check had zero callers so "checks" was always [].
  # The status helpers now record through the context set by the engines.
  json_set_context "disk" "System" "SAFE"
  status_ok "disk healthy" >/dev/null
  status_warn "disk warming" >/dev/null
  status_fail "disk critical" >/dev/null
  status_info "disk usage 62%" >/dev/null
  json_build_output 80 "Good" 1 1 >"$TEST_BASE/wired.json"
  [ -s "$TEST_BASE/wired.json" ] || fail "json_build_output emitted an empty document"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$TEST_BASE/wired.json" <<'PYEOF' || fail "checks array was not populated by the status helpers"
import json, sys
with open(sys.argv[1]) as f:
    doc = json.load(f)
assert len(doc["checks"]) == 4, "expected 4 check entries, got %d" % len(doc["checks"])
assert [c["status"] for c in doc["checks"]] == ["ok", "warn", "fail", "info"], "status sequence mismatch"
for c in doc["checks"]:
    assert c["module"] == "disk", "module mismatch: %r" % c["module"]
    assert c["category"] == "System", "category mismatch: %r" % c["category"]
    assert c["risk"] == "SAFE", "risk mismatch: %r" % c["risk"]
assert [c["message"] for c in doc["checks"]] == ["disk healthy", "disk warming", "disk critical", "disk usage 62%"]
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    jq -e '.checks | length == 4' "$TEST_BASE/wired.json" >/dev/null 2>&1 \
      || fail "checks array was not populated by the status helpers (jq)"
  else
    skip "no JSON parser available (need python3 or jq)"
  fi
}

@test "status helpers record nothing when JSON is disabled" {
  JSON_ENABLED=false
  json_set_context "disk" "System" "SAFE"
  status_ok "disk healthy" >/dev/null
  status_warn "disk warming" >/dev/null
  json_build_output 96 "Excellent" 1 0 >"$TEST_BASE/off.json"
  [ -s "$TEST_BASE/off.json" ] || fail "json_build_output emitted an empty document"
  assert_contains "$TEST_BASE/off.json" '"checks": \[\]'
}
