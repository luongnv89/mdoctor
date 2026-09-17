#!/usr/bin/env bats
#
# test_platform_copy.bats
# Issue #109 (task 12.6): platform-correct check copy and remediation
# advice — no macOS-only strings on Linux, and the Linux cleanup paths
# (crash filters, trash .trashinfo pairing) actually work.
#
# Hermetic: HOME sandboxes under the shared fixture root, a sparse PATH
# farm (git/docker hidden where a branch must see them missing or
# failing), MDOCTOR_POWER_SUPPLY_ROOT pointing at a staged sysfs tree,
# and DAYS_OLD_OVERRIDE where a real system dir could otherwise match.
# Bash 3.2 compatible: indexed arrays and [ ] tests only.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/safety.sh"

_CMD_TIMEOUT=120

_run_lim() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_CMD_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# _line_of NEEDLE FILE — first matching line number, empty when absent.
_line_of() {
  grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1
}

# _in_gate FILE LINENO PRED — rc 0 when LINENO sits inside the THEN arm
# of an `if is_<pred>` block (elif/else arms and post-fi lines don't
# count). Nested if/fi depth is tracked in awk.
_in_gate() {
  awk -v target="$2" -v pred="$3" '
    /^[[:space:]]*if[[:space:]]/ { depth++; gated[depth] = ($0 ~ pred) ? 1 : 0; alt[depth] = 0 }
    /^[[:space:]]*(elif|else)/   { if (depth > 0) alt[depth] = 1 }
    /^[[:space:]]*fi/            { if (depth > 0) depth-- }
    NR == target {
      ok = 1
      for (i = depth; i >= 1; i--) if (gated[i] && !alt[i]) ok = 0
      exit ok
    }
    END { if (NR < target) exit 1 }
  ' "$1"
}

# _in_gate_else FILE LINENO PRED — rc 0 when LINENO sits inside an
# elif/else arm of an `if is_<pred>` block (the non-matching side).
_in_gate_else() {
  awk -v target="$2" -v pred="$3" '
    /^[[:space:]]*if[[:space:]]/ { depth++; gated[depth] = ($0 ~ pred) ? 1 : 0; alt[depth] = 0 }
    /^[[:space:]]*(elif|else)/   { if (depth > 0) alt[depth] = 1 }
    /^[[:space:]]*fi/            { if (depth > 0) depth-- }
    NR == target {
      ok = 1
      for (i = depth; i >= 1; i--) if (gated[i] && alt[i]) ok = 0
      exit ok
    }
    END { if (NR < target) exit 1 }
  ' "$1"
}

# _macos_gated FILE LINENO — rc 0 when LINENO is macOS-gated, either
# textually (inside an `if is_macos` then-arm) or by function boundary
# (inside a function named *_macos, which only runs under is_macos).
_macos_gated() {
  _in_gate "$1" "$2" 'is_macos' && return 0
  awk -v target="$2" '
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/ {
      fn = $0; sub(/[[:space:]]*\(\).*/, "", fn); fstart = NR
    }
    NR == target { exit (fn ~ /_macos$/ && fstart < target) ? 0 : 1 }
  ' "$1"
}

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-platcopy.$(fixture_run_id).XXXXXX")"
  fixture_trap_cleanup "$TEST_TMP"
  export TEST_TMP
  mkdir -p "$TEST_TMP/farm" "$TEST_TMP/stubbin" "$TEST_TMP/home/.config/mdoctor"
  printf '# empty whitelist for test\n' > "$TEST_TMP/home/.config/mdoctor/cleanup_whitelist"
  # In-process safety calls must stay inside the sandbox: whitelist-file
  # location + HOME are bound here (same convention as
  # test_safety_validation.bats) so load_cleanup_whitelist never writes
  # to the developer's real home.
  export HOME="$TEST_TMP/home"
  export MDOCTOR_CLEANUP_WHITELIST_FILE="$TEST_TMP/home/.config/mdoctor/cleanup_whitelist"

  # Sparse PATH farm (house pattern): every host binary except the ones a
  # test must hide — git (forces the git_config install-advice branch)
  # and docker (replaced by the stubbin script below). ping/nslookup/ss/
  # ps stay excluded so unrelated probes degrade silently.
  local _d _f _b _p _need
  for _d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
      [ -f "$_f" ] || continue
      _b="$(basename "$_f")"
      case "$_b" in
        git|docker|ping|nslookup|ss|ps|softwareupdate) continue ;;
      esac
      [ -e "$TEST_TMP/farm/$_b" ] || ln -s "$_f" "$TEST_TMP/farm/$_b"
    done
  done
  for _need in bash env sh; do
    if [ ! -e "$TEST_TMP/farm/$_need" ]; then
      _p="$(command -v "$_need" 2>/dev/null || true)"
      [ -n "$_p" ] && ln -s "$_p" "$TEST_TMP/farm/$_need"
    fi
  done

  # docker stub: CLI present, `docker info` fails (daemon down) — drives
  # the remediation branch of checks/containers.sh deterministically.
  cat > "$TEST_TMP/stubbin/docker" <<'EOF'
#!/usr/bin/env bash
case "${1-}" in
  info)       exit 1 ;;
  --version)  echo "Docker version 27.0.0, build stub"; exit 0 ;;
  *)          exit 0 ;;
esac
EOF
  chmod +x "$TEST_TMP/stubbin/docker"
}

teardown_file() {
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  return 0
}

# ---------------------------------------------------------------------------
# Acceptance: every 'desktop Mac'/'open -a Docker'/'xcode-select' string in
# checks/ sits inside a platform gate (verified structurally + the Linux
# behaviour tests below prove the strings never fire on Linux).
# ---------------------------------------------------------------------------

@test "copy strings: every 'desktop Mac'/'open -a Docker'/'xcode-select' sits in an is_macos arm" {
  # Structural half of the acceptance grep — for every match in checks/,
  # the matched line must sit inside an `if is_macos` then-arm or a
  # *_macos helper (the battery module gates by function boundary).
  local f ln bad=""
  for f in "$ROOT_DIR"/checks/*.sh; do
    for ln in $(grep -n 'desktop Mac\|open -a Docker\|xcode-select' "$f" | cut -d: -f1); do
      _macos_gated "$f" "$ln" || bad="$bad ${f##*/}:$ln"
    done
  done
  [ -z "$bad" ] || fail "macOS-only strings outside a macOS gate:$bad"
}

@test "battery copy: 'desktop Mac' exists only inside the macOS arm" {
  local hits h
  hits="$(grep -n 'desktop Mac' "$ROOT_DIR/checks/battery.sh" | cut -d: -f1)"
  [ -n "$hits" ] || fail "expected the macOS-only 'desktop Mac' copy to remain in checks/battery.sh"
  for h in $hits; do
    _macos_gated "$ROOT_DIR/checks/battery.sh" "$h" \
      || fail "'desktop Mac' at battery.sh:$h is not macOS-gated"
  done
  # And the Linux arm must exist with neutral copy.
  grep -q 'is_linux' "$ROOT_DIR/checks/battery.sh" || fail "checks/battery.sh has no is_linux arm"
  grep -q 'power_supply' "$ROOT_DIR/checks/battery.sh" || fail "Linux battery arm does not read power_supply"
}

@test "containers copy: 'open -a Docker' inside is_macos, 'systemctl start docker' in the else arm" {
  local f="$ROOT_DIR/checks/containers.sh"
  local opena sysd
  opena="$(_line_of 'open -a Docker' "$f")"
  sysd="$(_line_of 'systemctl start docker' "$f")"
  [ -n "$opena" ] || fail "containers.sh lost the macOS open -a remediation"
  [ -n "$sysd" ]  || fail "containers.sh missing the Linux systemctl remediation"
  _in_gate "$f" "$opena" 'is_macos' \
    || fail "'open -a Docker' (line $opena) is not inside an is_macos arm"
  _in_gate_else "$f" "$sysd" 'is_macos' \
    || fail "'systemctl start docker' (line $sysd) is not inside the non-macOS arm"
}

@test "git_config copy: 'xcode-select' inside is_macos, package-manager advice on Linux" {
  local f="$ROOT_DIR/checks/git_config.sh"
  local xc
  xc="$(_line_of 'xcode-select' "$f")"
  [ -n "$xc" ] || fail "git_config.sh lost its xcode-select install advice"
  _in_gate "$f" "$xc" 'is_macos' \
    || fail "'xcode-select' (line $xc) is not inside an is_macos arm"
  # A Linux arm must exist — apt on Debian-family, pacman on
  # Arch-family, generic advice elsewhere (same shape as
  # checks/devtools.sh).
  grep -q 'is_debian' "$f" || fail "git_config.sh has no is_debian arm"
  grep -q 'is_arch' "$f" || fail "git_config.sh has no is_arch arm"
  grep -q 'apt install git' "$f" || fail "git_config.sh missing 'apt install git' Linux advice"
  grep -q 'pacman -S git' "$f" || fail "git_config.sh missing 'pacman -S git' Linux advice"
}

# ---------------------------------------------------------------------------
# Battery — Linux sysfs path (fixture root via MDOCTOR_POWER_SUPPLY_ROOT).
# ---------------------------------------------------------------------------

@test "battery: Linux with a battery present reports it, never 'desktop Mac'" {
  is_linux || { skip "linux-only lane"; return 0; }
  local ps="$TEST_TMP/power_supply"
  mkdir -p "$ps/BAT0" "$ps/ADP1"
  printf 'Battery\n' > "$ps/BAT0/type"
  printf '1\n'       > "$ps/BAT0/present"
  printf '63\n'      > "$ps/BAT0/capacity"
  printf 'Full\n'    > "$ps/BAT0/status"
  printf '384\n'     > "$ps/BAT0/cycle_count"
  printf '4046000\n' > "$ps/BAT0/charge_full"
  printf '6330000\n' > "$ps/BAT0/charge_full_design"
  printf 'bq20z451\n' > "$ps/BAT0/model_name"
  printf 'SMP\n'     > "$ps/BAT0/manufacturer"
  printf 'Mains\n'   > "$ps/ADP1/type"

  local out="$TEST_TMP/battery_linux.out"
  PATH="$TEST_TMP/farm" HOME="$TEST_TMP/home" \
    MDOCTOR_POWER_SUPPLY_ROOT="$ps" \
    _run_lim ./mdoctor check -m battery >"$out" 2>&1 || true
  assert_contains "$out" "Battery Health"
  assert_contains "$out" "BAT0"
  assert_contains "$out" "63%"
  assert_contains "$out" "cycle count: 384"
  assert_not_contains "$out" "desktop Mac"
  # health = 4046000/6330000 ≈ 63% → below 80% warning.
  assert_contains "$out" "Battery health: 63%"
  # The mains adapter must never count as a battery.
  assert_not_contains "$out" "ADP1:"
}

@test "battery: Linux with no battery prints neutral copy, not 'desktop Mac'" {
  is_linux || { skip "linux-only lane"; return 0; }
  local ps="$TEST_TMP/power_supply_empty"
  mkdir -p "$ps/ADP1"
  printf 'Mains\n' > "$ps/ADP1/type"

  local out="$TEST_TMP/battery_nobatt.out"
  PATH="$TEST_TMP/farm" HOME="$TEST_TMP/home" \
    MDOCTOR_POWER_SUPPLY_ROOT="$ps" \
    _run_lim ./mdoctor check -m battery >"$out" 2>&1 || true
  assert_contains "$out" "No battery detected. Skipping battery checks."
  assert_not_contains "$out" "desktop Mac"
}

# ---------------------------------------------------------------------------
# containers — daemon-down remediation is platform-correct.
# ---------------------------------------------------------------------------

@test "containers: docker-down advice is platform-correct" {
  local out="$TEST_TMP/containers_down.out"
  PATH="$TEST_TMP/stubbin:$TEST_TMP/farm" HOME="$TEST_TMP/home" \
    _run_lim ./mdoctor check -m containers >"$out" 2>&1 || true
  assert_contains "$out" "daemon is not running"
  if is_macos; then
    assert_contains "$out" "open -a Docker"
  else
    assert_contains "$out" "systemctl start docker"
    assert_not_contains "$out" "open -a Docker"
  fi
}

# ---------------------------------------------------------------------------
# git_config — install advice is platform-correct (git hidden from PATH).
# ---------------------------------------------------------------------------

@test "git_config: missing-git advice is platform-correct" {
  local out="$TEST_TMP/git_missing.out"
  PATH="$TEST_TMP/farm" HOME="$TEST_TMP/home" \
    _run_lim ./mdoctor check -m git_config >"$out" 2>&1 || true
  assert_contains "$out" "Git is not installed"
  if is_macos; then
    assert_contains "$out" "xcode-select --install"
  elif is_arch; then
    assert_contains "$out" "pacman -S git"
    assert_not_contains "$out" "xcode-select"
  elif is_debian; then
    assert_contains "$out" "apt install git"
    assert_not_contains "$out" "xcode-select"
  else
    assert_contains "$out" "package manager"
    assert_not_contains "$out" "xcode-select"
  fi
}

# ---------------------------------------------------------------------------
# trash — freedesktop pairing: files/<n> removed with info/<n>.trashinfo.
# ---------------------------------------------------------------------------

@test "trash: Linux deletes each .trashinfo entry alongside its file" {
  is_linux || { skip "linux-only lane"; return 0; }
  local home="$TEST_TMP/trashhome"
  mkdir -p "$home/.local/share/Trash/files" "$home/.local/share/Trash/info" \
    "$home/.config/mdoctor"
  printf '# empty\n' > "$home/.config/mdoctor/cleanup_whitelist"
  echo payload > "$home/.local/share/Trash/files/foo.txt"
  printf '[Trash Info]\nPath=/x\nDeletionDate=2026-01-01T00:00:00\n' \
    > "$home/.local/share/Trash/info/foo.txt.trashinfo"
  # An orphaned entry (file already gone) must also be swept — it is the
  # same phantom-UI bug with the payload missing.
  echo orphan > "$home/.local/share/Trash/info/orphan.trashinfo"

  # Dry-run keeps both members of the pair.
  HOME="$home" _run_lim ./mdoctor clean -m trash >"$TEST_TMP/trash_dry.out" 2>&1 || true
  assert_file_exists "$home/.local/share/Trash/files/foo.txt"
  assert_file_exists "$home/.local/share/Trash/info/foo.txt.trashinfo"

  MDOCTOR_ASSUME_YES=true HOME="$home" \
    _run_lim ./mdoctor clean --force -m trash >"$TEST_TMP/trash_force.out" 2>&1 || true
  assert_file_not_exists "$home/.local/share/Trash/files/foo.txt"
  assert_file_not_exists "$home/.local/share/Trash/info/foo.txt.trashinfo"
  assert_file_not_exists "$home/.local/share/Trash/info/orphan.trashinfo"
  assert_dir_exists "$home/.local/share/Trash/files"
  assert_dir_exists "$home/.local/share/Trash/info"
}

# ---------------------------------------------------------------------------
# crash_reports — Linux filters: apport *.crash + systemd-coredump core.*.
# ---------------------------------------------------------------------------

@test "crash_reports: Linux dirs cover apport and systemd-coredump" {
  is_linux || { skip "linux-only lane"; return 0; }
  local dirs
  dirs="$(platform_crash_dirs)"
  case "$dirs" in
    *"/var/crash"*) : ;;
    *) fail "platform_crash_dirs lost /var/crash: $dirs" ;;
  esac
  case "$dirs" in
    *".local/share/apport"*) : ;;
    *) fail "platform_crash_dirs lost the apport user dir: $dirs" ;;
  esac
  case "$dirs" in
    *"/var/lib/systemd/coredump"*) : ;;
    *) fail "platform_crash_dirs missing systemd-coredump dir: $dirs" ;;
  esac
  # Every emitted dir must pass the same validators deletions go through.
  local d rc
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    rc=0
    validate_deletion_path "$d" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "crash dir '$d' rejected by validate_deletion_path (rc=$rc)"
  done <<< "$dirs"
  # Per-dir filters: coredump names only in the systemd dir.
  [ "$(platform_crash_name_patterns /var/lib/systemd/coredump)" = "core.*" ] \
    || fail "coredump dir should filter on core.*"
  case "$(platform_crash_name_patterns /var/crash)" in
    *"*.crash"*) : ;;
    *) fail "apport dir should filter on *.crash" ;;
  esac
}

@test "crash_reports: Linux filter deletes aged .crash only (in-process, hermetic)" {
  is_linux || { skip "linux-only lane"; return 0; }
  local home="$TEST_TMP/home"   # exported sandbox HOME from setup_file
  mkdir -p "$home/.local/share/apport"
  echo old > "$home/.local/share/apport/old.crash"
  echo new > "$home/.local/share/apport/new.crash"
  echo keep > "$home/.local/share/apport/notes.txt"
  touch -d "40 days ago" "$home/.local/share/apport/old.crash" 2>/dev/null \
    || touch -t 202001010000 "$home/.local/share/apport/old.crash"

  # Drive the same validators the module uses — DRY_RUN=false is the
  # only state that deletes (fail-closed contract of is_dry_run).
  local -a name_args=() _p _first=1
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if [ "$_first" -eq 1 ]; then
      name_args+=("(" -name "$_p"); _first=0
    else
      name_args+=(-o -name "$_p")
    fi
  done < <(platform_crash_name_patterns "$home/.local/share/apport")
  name_args+=(")")
  local rc=0
  DRY_RUN=false safe_find_delete "$home/.local/share/apport" -type f \
    "${name_args[@]}" -mtime "+30" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "safe_find_delete on apport fixture returned $rc"
  assert_file_not_exists "$home/.local/share/apport/old.crash"
  assert_file_exists "$home/.local/share/apport/new.crash"
  assert_file_exists "$home/.local/share/apport/notes.txt"
}

@test "crash_reports: module scans the systemd-coredump dir on Linux" {
  is_linux || { skip "linux-only lane"; return 0; }
  local home="$TEST_TMP/crashhome2"
  mkdir -p "$home/.local/share/apport" "$home/.config/mdoctor"
  printf '# empty\n' > "$home/.config/mdoctor/cleanup_whitelist"
  echo old > "$home/.local/share/apport/old.crash"
  touch -d "40 days ago" "$home/.local/share/apport/old.crash" 2>/dev/null \
    || touch -t 202001010000 "$home/.local/share/apport/old.crash"

  # DAYS_OLD_OVERRIDE huge → nothing anywhere matches, so the run is
  # hermetic even where the real /var/lib/systemd/coredump exists.
  MDOCTOR_ASSUME_YES=true HOME="$home" DAYS_OLD_OVERRIDE=99999 \
    _run_lim ./mdoctor clean --force -m crash_reports \
    >"$TEST_TMP/crash_force.out" 2>&1 || true
  assert_contains "$TEST_TMP/crash_force.out" "coredump"
  assert_contains "$TEST_TMP/crash_force.out" "apport"
  assert_file_exists "$home/.local/share/apport/old.crash"
}

# ---------------------------------------------------------------------------
# shell — source-target rules: expand vars, skip bare relative, [[:space:]].
# ---------------------------------------------------------------------------

@test "shell: fixture .zshrc with rustup/nvm/oh-my-zsh lines produces zero false warnings" {
  local home="$TEST_TMP/shellhome"
  mkdir -p "$home/.cargo" "$home/.nvm" "$home/.oh-my-zsh" "$home/.config/mdoctor"
  printf '# empty\n' > "$home/.config/mdoctor/cleanup_whitelist"
  echo '# rustup env' > "$home/.cargo/env"
  echo '# nvm'        > "$home/.nvm/nvm.sh"
  echo '# omz'        > "$home/.oh-my-zsh/oh-my-zsh.sh"
  cat > "$home/.zshrc" <<'EOF'
# fixture .zshrc — common tool source lines
. "$HOME/.cargo/env"
. "$NVM_DIR/nvm.sh"
. "$ZSH/oh-my-zsh.sh"
source foo.sh
source ./local.sh
source sub/dir/script.sh
source /nonexistent-mdoctor-109/abs.sh
EOF

  local out="$TEST_TMP/shell_zshrc.out"
  PATH="$TEST_TMP/farm" HOME="$home" \
    NVM_DIR="$home/.nvm" ZSH="$home/.oh-my-zsh" \
    _run_lim ./mdoctor check -m shell >"$out" 2>&1 || true
  # The three tool lines and every relative target resolve or are skipped —
  # only the truly-missing absolute path may warn.
  assert_not_contains "$out" "cargo/env"
  assert_not_contains "$out" "nvm.sh"
  assert_not_contains "$out" "oh-my-zsh.sh"
  assert_not_contains "$out" "foo.sh"
  assert_not_contains "$out" "local.sh"
  assert_not_contains "$out" "dir/script.sh"
  local warns
  warns="$(grep -c 'sources missing file' "$out" || true)"
  [ "$warns" = "1" ] || { cat "$out" >&2; fail "expected exactly 1 missing-source warning, got $warns"; }
  assert_contains "$out" "abs.sh"
}

@test "shell: no GNU-only \\s remains in the source-line matching" {
  # \s is a GNU grep-ism — POSIX/shell regex needs [[:space:]].
  if grep -n '\\s' "$ROOT_DIR/checks/shell.sh" >/dev/null 2>&1; then
    grep -n '\\s' "$ROOT_DIR/checks/shell.sh" >&2
    fail "checks/shell.sh still uses GNU-only \\s"
  fi
}
