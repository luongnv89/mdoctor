#!/usr/bin/env bats
#
# Regression test for issue #106 (Task 12.3):
#   the safe cleanup mode is named and declared everywhere it runs.
#   - `clean --dry-run` / `-n` are accepted as the explicit form of the
#     default (previously rejected with "Unknown option").
#   - The interactive menu heading states the mode, and the resolved
#     selection is restated with it before the first module runs.
#   - Every cleanup run — full, interactive, single-module — opens with a
#     mode banner and terminates with a deleted/would-free summary.
#   - Both pre-flight summaries name the whitelist file and what it is for.
#   - The single-module check path ends with the same counts and
#     terminator the full run emits.
# Flag conflicts resolve last-wins: a `--dry-run` after `--force` keeps the
# run dry; a `--force` after `--dry-run` re-arms the confirmation gate.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME TRASH_DIR
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-modeux.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"
  TRASH_DIR="$TMPHOME/$(basename "$(platform_trash_dir)")"
  if is_linux; then
    TRASH_DIR="$TMPHOME/.local/share/Trash/files"
  fi
  mkdir -p "$TRASH_DIR" "$TMPHOME/.config/mdoctor"
  printf '# empty\n' >"$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

teardown_file() {
  rm -rf "$TMPHOME"
}

# _victim NAME — drop a fresh victim file in the sandbox trash and print
# its path (each test re-creates its own, so ordering cannot matter).
_victim() {
  local f="$TRASH_DIR/$1"
  echo "sample" >"$f"
  printf '%s\n' "$f"
}

@test "clean --dry-run and -n are accepted as the explicit safe mode" {
  local victim
  victim="$(_victim explicit_dry.txt)"
  # Single-module path: exit 0, names the mode, deletes nothing.
  HOME="$TMPHOME" ./mdoctor clean --dry-run -m trash >"$TMPHOME/dry_flag.out" 2>&1
  assert_contains "$TMPHOME/dry_flag.out" "dry-run mode"
  assert_file_exists "$victim"

  HOME="$TMPHOME" ./mdoctor clean -n -m trash >"$TMPHOME/n_flag.out" 2>&1
  assert_contains "$TMPHOME/n_flag.out" "dry-run mode"
  assert_file_exists "$victim"

  # Full-run path: exit 0 and the engine's banner names the mode.
  HOME="$TMPHOME" ./mdoctor clean --dry-run >"$TMPHOME/dry_full.out" 2>&1
  assert_contains "$TMPHOME/dry_full.out" "dry-run mode"
  assert_file_exists "$victim"
}

@test "flag conflicts resolve last-wins: --force --dry-run stays dry" {
  local victim
  victim="$(_victim last_wins.txt)"
  # --force --dry-run: the later flag cancels force — no confirmation
  # gate, nothing deleted, exit 0.
  printf 'y\n' | HOME="$TMPHOME" ./mdoctor clean --force --dry-run -m trash \
    >"$TMPHOME/force_dry.out" 2>&1
  assert_contains "$TMPHOME/force_dry.out" "dry-run mode"
  assert_not_contains "$TMPHOME/force_dry.out" "Proceed with deletion"
  assert_file_exists "$victim"

  # --dry-run --force: the later flag re-arms the destructive path —
  # refused on a non-tty without MDOCTOR_ASSUME_YES (fail closed).
  local rc=0
  HOME="$TMPHOME" ./mdoctor clean --dry-run --force -m trash </dev/null \
    >"$TMPHOME/dry_force.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "Expected refusal for 'clean --dry-run --force' without confirmation"
  assert_contains "$TMPHOME/dry_force.out" "force mode"
  assert_contains "$TMPHOME/dry_force.out" "MDOCTOR_ASSUME_YES"
  assert_file_exists "$victim"
}

@test "interactive menu heading names the mode (-i and -i --force differ)" {
  HOME="$TMPHOME" ./mdoctor clean -i </dev/null >"$TMPHOME/menu_dry.out" 2>&1
  HOME="$TMPHOME" ./mdoctor clean -i --force </dev/null >"$TMPHOME/menu_force.out" 2>&1
  assert_contains "$TMPHOME/menu_dry.out" "dry-run mode"
  assert_not_contains "$TMPHOME/menu_dry.out" "force mode"
  assert_contains "$TMPHOME/menu_force.out" "force mode"
  if cmp -s "$TMPHOME/menu_dry.out" "$TMPHOME/menu_force.out"; then
    fail "clean -i and clean -i --force rendered identical menus"
  fi
}

@test "resolved selection is restated with the mode before the first module" {
  printf '1\n' | HOME="$TMPHOME" ./mdoctor clean -i >"$TMPHOME/sel_dry.out" 2>&1
  assert_contains "$TMPHOME/sel_dry.out" "Selected: trash — dry-run mode"
  # The restatement precedes the first module banner.
  local sel_line run_line
  sel_line="$(grep -n 'Selected: ' "$TMPHOME/sel_dry.out" | head -1 | cut -d: -f1)"
  run_line="$(grep -n 'Running cleanup module' "$TMPHOME/sel_dry.out" | head -1 | cut -d: -f1)"
  [ -n "$sel_line" ] && [ -n "$run_line" ] \
    || fail "missing Selected/Running lines in interactive output"
  [ "$sel_line" -lt "$run_line" ] \
    || fail "mode restatement did not precede the first module run"
  # Interactive run terminates with a completion line naming the mode.
  assert_contains "$TMPHOME/sel_dry.out" "Interactive cleanup finished (dry-run mode)"
}

@test "single-module cleanup opens with a mode banner and closes with a summary" {
  local victim
  victim="$(_victim banner.txt)"
  HOME="$TMPHOME" ./mdoctor clean -m trash >"$TMPHOME/mod_dry.out" 2>&1
  assert_contains "$TMPHOME/mod_dry.out" "Cleanup module: trash — dry-run mode"
  assert_contains "$TMPHOME/mod_dry.out" "Cleanup finished: trash (dry-run mode)"
  assert_contains "$TMPHOME/mod_dry.out" "Nothing was deleted"
  assert_file_exists "$victim"

  victim="$(_victim banner_force.txt)"
  MDOCTOR_ASSUME_YES=true HOME="$TMPHOME" ./mdoctor clean --force -m trash \
    >"$TMPHOME/mod_force.out" 2>&1
  assert_contains "$TMPHOME/mod_force.out" "Cleanup module: trash — force mode"
  assert_contains "$TMPHOME/mod_force.out" "Cleanup finished: trash (force mode)"
  assert_contains "$TMPHOME/mod_force.out" "Estimated space freed"
  assert_file_not_exists "$victim"
}

@test "both pre-flight summaries name the whitelist file and its purpose" {
  local victim
  victim="$(_victim whitelist.txt)"
  # Single-module force pre-flight (refused: 'n' at the gate).
  printf 'n\n' | HOME="$TMPHOME" ./mdoctor clean --force -m trash \
    >"$TMPHOME/pf_mod.out" 2>&1 || true
  assert_contains "$TMPHOME/pf_mod.out" "Pre-flight Safety Summary"
  assert_contains "$TMPHOME/pf_mod.out" "Whitelist file: $TMPHOME/.config/mdoctor/cleanup_whitelist"
  assert_contains "$TMPHOME/pf_mod.out" "never deleted"
  assert_file_exists "$victim"

  # Full-engine force pre-flight (preflight-only: no destructive step runs).
  MDOCTOR_PREFLIGHT_ONLY=true HOME="$TMPHOME" ./cleanup.sh --force \
    >"$TMPHOME/pf_full.out" 2>&1 || true
  assert_contains "$TMPHOME/pf_full.out" "Pre-flight Safety Summary"
  assert_contains "$TMPHOME/pf_full.out" "Whitelist file: $TMPHOME/.config/mdoctor/cleanup_whitelist"
  assert_contains "$TMPHOME/pf_full.out" "never deleted"
  assert_file_exists "$victim"
}

@test "whitelist file creation is announced, never silent" {
  rm -f "$TMPHOME/.config/mdoctor/cleanup_whitelist"
  HOME="$TMPHOME" ./mdoctor clean -m trash >"$TMPHOME/wl_create.out" 2>&1
  assert_contains "$TMPHOME/wl_create.out" "created $TMPHOME/.config/mdoctor/cleanup_whitelist"
  printf '# empty\n' >"$TMPHOME/.config/mdoctor/cleanup_whitelist"
}

@test "single-module check ends with the full run's counts and terminator" {
  # The terminator is module-independent; `system` stands in for `network`
  # (issue AC) because the network probes can hang hermetic CI PATH farms.
  HOME="$TMPHOME" ./mdoctor check -m system >"$TMPHOME/check_mod.out" 2>&1
  assert_contains "$TMPHOME/check_mod.out" "Health score:"
  assert_contains "$TMPHOME/check_mod.out" "Warnings:"
  assert_contains "$TMPHOME/check_mod.out" "Done."
  # The terminator is genuinely last — no silent truncation after it.
  tail -n 1 "$TMPHOME/check_mod.out" | grep -q "Done" \
    || fail "check -m output did not terminate with the full run's 'Done.'"
}

@test "cleanup.sh accepts --dry-run and -n as the explicit safe mode" {
  local victim
  victim="$(_victim engine_dry.txt)"
  HOME="$TMPHOME" ./cleanup.sh --dry-run >"$TMPHOME/eng_dry.out" 2>&1
  assert_contains "$TMPHOME/eng_dry.out" "dry-run mode"
  assert_file_exists "$victim"
  HOME="$TMPHOME" ./cleanup.sh -n >"$TMPHOME/eng_n.out" 2>&1
  assert_contains "$TMPHOME/eng_n.out" "dry-run mode"
  assert_file_exists "$victim"
}

@test "clean --help documents -n/--dry-run and the whitelist file" {
  HOME="$TMPHOME" ./mdoctor clean --help >"$TMPHOME/clean_help.out" 2>&1
  assert_contains "$TMPHOME/clean_help.out" "--dry-run"
  assert_contains "$TMPHOME/clean_help.out" "-n"
  assert_contains "$TMPHOME/clean_help.out" "Whitelist file"
}
