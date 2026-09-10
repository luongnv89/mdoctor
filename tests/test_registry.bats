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
  count=$(grep -rn "^register_all_modules()" --include='*.sh' --include='mdoctor' --include='doctor.sh' "$REPO_ROOT" | grep -v tests/ | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
  grep -q "lib/registry.sh" "${REPO_ROOT}/mdoctor"
}

@test "doctor.sh carries no register_module duplicate" {
  count=$(grep -c '^  register_module\|^register_module' "${REPO_ROOT}/doctor.sh" || true)
  [ "$count" -eq 0 ]
}

@test "apt appears in help and both Available-modules errors (derived)" {
  run "$REPO_ROOT/mdoctor" help
  [[ "$output" == *"apt [MED]"* ]]
  run "$REPO_ROOT/mdoctor" clean -m bogus_nope_xyz
  [[ "$output" == *"apt"* ]]
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
