#!/usr/bin/env bats
#
# Regression test for Task 8.6 (#80):
#   check_storage delegates to six named scan functions plus one report
#   helper; the parallel label/path arrays (with placeholders and a magic
#   starting index) are a single delimited list where front-insertion
#   labels correctly.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

setup() {
  cd "$ROOT_DIR" || return 1
  export MDOCTOR_DEBUG=false
  BOLD=""; RESET=""
  export BOLD RESET
  STEP_CURRENT=0; STEP_TOTAL=1
  export STEP_CURRENT STEP_TOTAL
  ACTIONS=()
  WARN_COUNT=0; FAIL_COUNT=0
  export WARN_COUNT FAIL_COUNT
  source "$ROOT_DIR/lib/constants.sh"
  source "$ROOT_DIR/lib/platform.sh"
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/logging.sh"
  source "$ROOT_DIR/lib/disk.sh"
  source "$ROOT_DIR/lib/metadata.sh"
  source "$ROOT_DIR/lib/registry.sh"
  source "$ROOT_DIR/checks/storage.sh"
  init_colors >/dev/null 2>&1 || true
}

@test "check_storage is under 60 lines and delegates to six scans plus reporter" {
  start=$(grep -n '^check_storage()' "$ROOT_DIR/checks/storage.sh" | cut -d: -f1)
  body=$(sed -n "${start},/^}/p" "$ROOT_DIR/checks/storage.sh")
  count=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
  [ "$count" -lt 60 ]
  for fn in _storage_scan_appdata _storage_scan_applications _storage_scan_devtools _storage_scan_cloud _storage_scan_nodedeps _storage_scan_devcaches; do
    grep -q "^${fn}()" "$ROOT_DIR/checks/storage.sh" || fail "missing $fn"
    printf '%s\n' "$body" | grep -q "$fn" || fail "check_storage does not call $fn"
  done
  grep -q "^_storage_report()" "$ROOT_DIR/checks/storage.sh" || fail "missing report helper"
  for fn in _storage_scan_appdata _storage_scan_devtools _storage_scan_cloud _storage_scan_nodedeps _storage_scan_devcaches _storage_scan_static_caches; do
    fn_body=$(sed -n "/^${fn}()/,/^}/p" "$ROOT_DIR/checks/storage.sh")
    printf '%s\n' "$fn_body" | grep -q "_storage_report" || fail "$fn does not use the report helper"
  done
}

@test "no parallel label/path arrays, placeholders or magic start index" {
  leftover=$(grep -c 'cache_labels\|cache_paths\|start at index' "$ROOT_DIR/checks/storage.sh" || true)
  [ "$leftover" -eq 0 ]
}

@test "front-inserted cache entry is labelled correctly" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/frontprobe/sub" "$HOME/cargo/registry"
  # Real blocks, not sparse: du measures disk usage, and truncate leaves holes.
  dd if=/dev/zero of="$HOME/frontprobe/sub/f.bin" bs=1048576 count=105 2>/dev/null
  dd if=/dev/zero of="$HOME/cargo/registry/f.bin" bs=1048576 count=105 2>/dev/null
  STORAGE_TOTAL_KB=0; STORAGE_FOUND_ANY=false
  entries="Front Probe Masuk|${HOME}/frontprobe
Cargo registry|${HOME}/cargo/registry"
  out=$(_storage_scan_static_caches "$entries" 2>&1)
  [[ "$out" == *"Front Probe Masuk"* ]]
  [[ "$out" == *"Cargo registry"* ]]
  front_line=$(printf '%s\n' "$out" | grep -n "Front Probe Masuk" | cut -d: -f1)
  cargo_line=$(printf '%s\n' "$out" | grep -n "Cargo registry" | cut -d: -f1)
  [ "$front_line" -lt "$cargo_line" ]
}
