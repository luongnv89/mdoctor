#!/usr/bin/env bats
#
# Regression test for issue #10:
#   the cleanup-phase size probes once inlined
#   `du -sk <dir> 2>/dev/null | awk '{print $1}'` inside $(...) under
#   `set -euo pipefail`. When `du` hit a permission-denied item inside a
#   target directory it exited non-zero while still printing a partial
#   total — the pipeline failed and errexit aborted `mdoctor clean -f`
#   mid-module with no output (the same silent-exit symptom as issue #9,
#   one stage later).
#
#   The listed sites (cleanups/xcode.sh, cleanups/dev_caches.sh,
#   cleanups/ios_backups.sh, checks/storage.sh) now route through the
#   shared hardened probe du_size_kb (lib/disk.sh) — often via the
#   size_cache_kb wrapper — where a partial du total is a genuine
#   measurement and keeps rc 0. tests/test_disk_library.bats already pins
#   "no du call site survives outside lib/disk.sh"; this file proves the
#   runtime behavior: a force run reaches its closing summary even when a
#   cleanup target contains permission-blocked items.
#
# Scope: cleanup-phase sites only — the pre-flight phase is covered by
# test_force_preflight_resilience.bats (issue #9).

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

setup_file() {
  cd "$ROOT_DIR" || return 1
  export TMPHOME
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TMPHOME="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-cleanres.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TMPHOME"

  # Hermetic stubs (also set by tests/run.sh; repeated here so this file
  # passes standalone): docker/apt-get/sudo record argv, never execute.
  export PATH="$ROOT_DIR/tests/helpers/bin:$PATH"

  # Private stubs for the two host binaries the cleanup-phase modules
  # shell out to when they exist: dev_caches runs `brew cleanup` /
  # `brew autoremove`, xcode runs `xcrun simctl delete unavailable`. On a
  # macOS dev box both resolve to the real tools — the stubs keep the
  # force-mode runs hermetic there (Linux CI lacks them anyway).
  local stubbin="$TMPHOME/stubbin"
  mkdir -p "$stubbin"
  local tool
  for tool in brew xcrun; do
    {
      printf '#!/usr/bin/env bash\n'
      printf 'if [ -n "${MDOCTOR_STUB_LOG:-}" ]; then printf "%%s %%s\\n" "%s" "$*" >>"$MDOCTOR_STUB_LOG"; fi\n' "$tool"
      printf 'exit 0\n'
    } >"$stubbin/$tool"
    chmod +x "$stubbin/$tool"
  done
  export PATH="$stubbin:$PATH"

  # Poisoned npm cache: a chmod-000 child makes `du -sk` exit non-zero
  # while still printing a partial total — the exact trigger the retired
  # `du | awk` pipelines died on under pipefail.
  mkdir -p "$TMPHOME/.npm/poisoned"
  echo "data" >"$TMPHOME/.npm/poisoned/file.txt"
  chmod 000 "$TMPHOME/.npm/poisoned"

  # Poisoned Xcode DerivedData (macOS-only module; created on Linux too
  # — inert there, keeps setup branch-free). A readable sibling gives du
  # a non-zero partial total so the module's measure-log-delete path runs
  # against the poisoned tree instead of taking the "empty" shortcut.
  local derived_data="$TMPHOME/Library/Developer/Xcode/DerivedData"
  mkdir -p "$derived_data/poisoned"
  echo "data" >"$derived_data/poisoned/file.txt"
  head -c 8192 /dev/zero >"$derived_data/readable.bin" 2>/dev/null \
    || dd if=/dev/zero of="$derived_data/readable.bin" bs=1024 count=8 2>/dev/null
  chmod 000 "$derived_data/poisoned"
}

teardown_file() {
  # Restore permissions so cleanup can succeed even where a poisoned dir
  # was made.
  if [ -d "${TMPHOME:-}" ]; then
    chmod -R u+rwx "$TMPHOME" 2>/dev/null || true
    rm -rf "$TMPHOME"
  fi
}

@test "force-mode full cleanup completes with a permission-blocked cache entry (issue #10)" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root bypasses mode checks — the du poison cannot fail"
  fi
  local out_file="$TMPHOME/clean-force.out"
  # `mdoctor clean -f` execs this same engine; allow non-zero exit (a
  # module may end "with errors" once rm meets the unreadable dir — the
  # regression was a SILENT abort, so assertions target the output trail).
  MDOCTOR_STUB_LOG="$TMPHOME/stub-full.log" MDOCTOR_ASSUME_YES=true \
    HOME="$TMPHOME" ./cleanup.sh --force >"$out_file" 2>&1 || true

  # The poisoned site was reached and handled (size line, "could not
  # determine" and "empty" all start with the label).
  assert_contains "$out_file" "Developer caches cleanup"
  assert_contains "$out_file" "npm cache"

  # Under the retired pattern the run died inside the first _clean_cache
  # call — nothing past it was ever printed. The module's own
  # node_modules scan and the engine's closing footer prove completion.
  assert_contains "$out_file" "Scanning for stale node_modules"
  assert_contains "$out_file" "Cleanup finished"
  assert_contains "$out_file" "Estimated space freed"
}

@test "mdoctor clean --force -m dev_caches completes with a permission-blocked entry (issue #10)" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root bypasses mode checks — the du poison cannot fail"
  fi
  local out_file="$TMPHOME/clean-module.out"
  MDOCTOR_STUB_LOG="$TMPHOME/stub-module.log" MDOCTOR_ASSUME_YES=true \
    HOME="$TMPHOME" ./mdoctor clean --force -m dev_caches >"$out_file" 2>&1 || true

  assert_contains "$out_file" "Cleanup module: dev_caches"
  assert_contains "$out_file" "Developer caches cleanup"
  assert_contains "$out_file" "npm cache"
  assert_contains "$out_file" "Scanning for stale node_modules"
  # The terminator may read "Cleanup finished:" or "Cleanup finished with
  # errors:" depending on whether the fs reports a nonzero partial total
  # (a >0 KB .npm proceeds to a delete attempt the unreadable dir fails).
  # Either way it printed — a silent mid-module abort prints neither.
  assert_contains "$out_file" "Cleanup finished"
}

@test "mdoctor clean --force -m xcode completes with a permission-blocked DerivedData (issue #10)" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "root bypasses mode checks — the du poison cannot fail"
  fi
  if ! is_macos; then
    skip "the xcode module is macOS-only"
  fi
  local out_file="$TMPHOME/clean-xcode.out"
  MDOCTOR_ASSUME_YES=true \
    HOME="$TMPHOME" ./mdoctor clean --force -m xcode >"$out_file" 2>&1 || true

  # The DerivedData site (formerly cleanups/xcode.sh:16) was reached and
  # its partial-size measurement logged; the run then continued to the
  # simulator steps and the module terminator instead of aborting cold.
  assert_contains "$out_file" "Xcode cleanup"
  assert_contains "$out_file" "Xcode DerivedData:"
  assert_contains "$out_file" "Removing unavailable simulators"
  assert_contains "$out_file" "Cleanup finished"
}
