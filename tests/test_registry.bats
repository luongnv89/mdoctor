#!/usr/bin/env bats
# Task 8.1 (#75): module registry is the single source of truth.
# - cleanup/check lists declared once (lib/registry.sh), not 13 places
# - apt appears in help + both "Available modules" error messages (derived)
# - doctor.sh carries no register_module duplicate; count derived
# - throwaway registry entry propagates to list/help/errors/dispatch lookup

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  source "${REPO_ROOT}/lib/platform.sh"
  source "${REPO_ROOT}/lib/metadata.sh"
  source "${REPO_ROOT}/lib/registry.sh"
  register_all_modules
}

@test "registry declared once: only lib/registry.sh defines register_all_modules" {
  # BusyBox-grep compatible (Bash 3.2 CI image has no grep --include).
  count=$(find "$REPO_ROOT" -type f \( -name '*.sh' -o -name mdoctor -o -name doctor.sh \) | grep -v 'tests/' | xargs grep -l '^register_all_modules()' | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  grep -q "lib/registry.sh" "${REPO_ROOT}/mdoctor"
}

@test "doctor.sh carries no register_module duplicate" {
  count=$(grep -v '^#' "${REPO_ROOT}/doctor.sh" | grep -c 'register_module' || true)
  [ "$count" -eq 0 ]
}

@test "dead metadata/platform helpers are gone (issue #91)" {
  # F-DEAD-003 / F-DEAD-006: unreferenced helpers were deleted, not kept.
  grep -n 'list_modules()' "${REPO_ROOT}/lib/metadata.sh" && return 1 || true
  grep -n 'is_supported_platform()' "${REPO_ROOT}/lib/platform.sh" && return 1 || true
}

@test "check dispatch reads the registry function column (issue #91)" {
  # F-DEAD-001: the single-module check dispatcher routes through
  # get_module_func instead of a hand-maintained case mapping.
  grep -q 'get_module_func "$module" check' "${REPO_ROOT}/mdoctor"
}

@test "help and Available-modules errors are registry-derived (platform-filtered)" {
  run "$REPO_ROOT/mdoctor" help
  if is_macos; then
    [[ "$output" == *"xcode [MED]"* ]]
    [[ "$output" != *"apt [MED]"* ]]
  else
    [[ "$output" == *"apt [MED]"* ]]
  fi
  run "$REPO_ROOT/mdoctor" clean -m bogus_nope_xyz
  local derived
  derived=$(registry_available_text cleanup "Available modules")
  [[ "$output" == *"$derived"* ]]
}

@test "throwaway registry entry propagates to names, help, errors and func lookup" {
  register_module cleanup throwaway_probe_xyz System LOW clean_trash "Throwaway probe"
  run registry_names cleanup
  [[ "$output" == *"throwaway_probe_xyz"* ]]
  run registry_available_text cleanup "Available modules"
  [[ "$output" == *"throwaway_probe_xyz"* ]]
  run registry_help_group cleanup
  [[ "$output" == *"throwaway_probe_xyz"* ]]
  [ "$(get_module_func throwaway_probe_xyz cleanup)" = "clean_trash" ]
  [ -n "$(get_module_desc throwaway_probe_xyz cleanup)" ]
}
