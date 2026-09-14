#!/usr/bin/env bats
#
# test_doc_examples.bats — issue #114 (task 13.1)
#
# Two layers:
#
# 1. Doc-example execution. Every command example inside the ```bash
#    fences of docs/GUIDEBOOK.md is executed against the ./mdoctor in
#    this tree on the lane the suite is running on, and none may be
#    REJECTED — "Unknown check/cleanup module", "Unknown fix target",
#    "Unknown option/command", "is macOS-only", "-m requires a module
#    name". A module that dispatches and reports findings (non-zero
#    rc) is not a rejection, so only deterministic commands are held
#    to rc==0 (clean in dry-run, info/list/history/version/help/
#    diagnose).
#
#    Platform routing: an example line carrying the same label the
#    tables use — `# macOS only` / `# Linux only` in its trailing
#    comment — is exercised on that lane and skipped on the other;
#    unlabeled examples run on both.
#
#    Hermetic: HOME is a fixture sandbox and stdin is /dev/null (the
#    interactive picker cancels cleanly on EOF). `clean` examples have
#    --force/-f rewritten to --dry-run before execution — doc examples
#    run dry-run only, never destructively — `fix` examples run under
#    DRY_RUN=true (the Task 4.4 opt-in every fix module honors), and a
#    bare `update` gains --check so the self-updater never applies for
#    real.
#    Env-assignment prefixes (DAYS_OLD_OVERRIDE=14 mdoctor ...) are
#    passed through `env`. Lines with a `<placeholder>` are usage
#    templates, not examples.
#
# 2. Label coverage. Every table row carries Both / macOS only /
#    Linux only, and every line naming a platform-scoped module
#    (xcode, ios_backups, bluetooth, usb, homebrew, spotlight,
#    timemachine, permissions, audio, wifi, apt, the `fix disk`
#    target) carries its platform label — the same grep the issue's
#    acceptance criteria run.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
GUIDEBOOK="$ROOT_DIR/docs/GUIDEBOOK.md"

source "$ROOT_DIR/lib/platform.sh"

_DOC_CMD_TIMEOUT=120

setup_file() {
  cd "$ROOT_DIR" || return 1
  FIXTURE_ROOT="$(fixture_root)"
  export FIXTURE_ROOT
  TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-docex.$(fixture_run_id).XXXXXX")"
  export TEST_TMP
  fixture_trap_cleanup "$TEST_TMP"
  TEST_HOME="$TEST_TMP/home"
  mkdir -p "$TEST_HOME"
  export TEST_HOME
}

teardown_file() {
  rm -rf "$TEST_TMP"
}

# _doc_fenced_lines — print "lineno<TAB>raw" for each line inside a
# ```bash fence of the guidebook.
_doc_fenced_lines() {
  awk '
    /^[[:space:]]*```bash[[:space:]]*$/ { inblock = 1; next }
    /^[[:space:]]*```[[:space:]]*$/     { inblock = 0; next }
    inblock { printf "%d\t%s\n", NR, $0 }
  ' "$GUIDEBOOK"
}

# _rejection_seen FILE — rc 0 when FILE holds an mdoctor dispatch
# refusal (the failure mode this test exists to catch).
_rejection_seen() {
  grep -qE 'Unknown check module|Unknown cleanup module|Unknown fix target|Unknown option|Unknown command|is macOS-only|requires a module name' "$1"
}

@test "guidebook is titled for mdoctor with no legacy product name" {
  local first_line
  first_line="$(head -n 1 "$GUIDEBOOK")"
  [ "$first_line" = "# mdoctor Guidebook" ] || fail "unexpected title: $first_line"
  assert_not_contains "$GUIDEBOOK" "Mac Doctor"
  assert_not_contains "$GUIDEBOOK" "mac-doctor"
}

@test "every command table row carries a platform label" {
  local bad="" line
  while IFS= read -r line; do
    case "$line" in
      *"macOS only"*|*"Linux only"*|*"Both"*) ;;
      *) bad="${bad}unlabeled row: ${line}\n" ;;
    esac
  done < <(grep -n '^|' "$GUIDEBOOK" | grep -v -- '---' | grep -v -- '| Platform |' || true)
  if [ -n "$bad" ]; then
    printf '%b' "$bad" >&2
    fail "guidebook table rows missing Both / macOS only / Linux only"
  fi
}

@test "platform-specific module names always carry their label" {
  local failures="" pair token want hits
  for pair in \
    "xcode:macOS only" "ios_backups:macOS only" "bluetooth:macOS only" \
    "usb:macOS only" "homebrew:macOS only" "spotlight:macOS only" \
    "timemachine:macOS only" "permissions:macOS only" "audio:macOS only" \
    "wifi:macOS only" "apt:Linux only"; do
    token="${pair%%:*}"
    want="${pair#*:}"
    hits="$(grep -n "$token" "$GUIDEBOOK" | grep -v -- "$want" || true)"
    if [ -n "$hits" ]; then
      failures="${failures}${token} needs '${want}':\n${hits}\n"
    fi
  done
  # `fix disk` is macOS-only even though `check -m disk` runs on both —
  # key on the fix-target spellings, not the bare name.
  hits="$(grep -nE 'fix +disk|`disk`' "$GUIDEBOOK" | grep -v -- 'macOS only' || true)"
  if [ -n "$hits" ]; then
    failures="${failures}fix disk needs 'macOS only':\n${hits}\n"
  fi
  if [ -n "$failures" ]; then
    printf '%b' "$failures" >&2
    fail "platform-specific names found without their platform label"
  fi
}

@test "apt is documented for check, clean and fix; Linux cache path is the XDG path" {
  grep -n 'check -m apt' "$GUIDEBOOK" | grep -q 'Linux only' \
    || fail "no Linux-only 'check -m apt' row"
  grep -n 'clean -m apt' "$GUIDEBOOK" | grep -q 'Linux only' \
    || fail "no Linux-only 'clean -m apt' row"
  grep -n 'fix apt' "$GUIDEBOOK" | grep -q 'Linux only' \
    || fail "no Linux-only 'fix apt' row"
  grep -q '~/.cache' "$GUIDEBOOK" || fail "guidebook lacks the Linux cache path ~/.cache"
  grep -q 'XDG' "$GUIDEBOOK" || fail "Linux cache path is not identified as the XDG path"
}

@test "every fenced command example executes without rejection" {
  local ran=0 skipped_macos=0 skipped_linux=0 templates=0
  local macos_examples=0 linux_examples=0
  local failures="" lineno raw line label
  while IFS=$'\t' read -r lineno raw; do
    # Trim leading whitespace; skip blanks and comment-only lines.
    line="${raw#"${raw%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    # Platform label lives in the trailing comment — read it off the
    # raw line before stripping.
    label="both"
    case "$raw" in
      *"macOS only"*) label="macos" ;;
      *"Linux only"*) label="linux" ;;
    esac

    # Strip the trailing comment, then any pipe consumer — the example
    # under test is the mdoctor command itself.
    line="${line%% #*}"
    line="${line%%|*}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in
      *\<*|*\>*) templates=$((templates + 1)); continue ;;
    esac

    # Tokenize: optional VAR=value prefixes, then `mdoctor`, then args.
    local -a toks=() envs=() args=()
    local seen=0 tok
    set -f
    toks=($line)
    set +f
    for tok in "${toks[@]}"; do
      if [ "$seen" -eq 0 ]; then
        case "$tok" in
          mdoctor) seen=1 ;;
          *=*)     envs+=("$tok") ;;
          *)       seen=-1 ;;
        esac
      else
        args+=("$tok")
      fi
    done
    [ "$seen" -eq 1 ] || continue   # not an mdoctor example line

    if [ "$label" = "macos" ]; then
      macos_examples=$((macos_examples + 1))
      is_macos || { skipped_macos=$((skipped_macos + 1)); continue; }
    elif [ "$label" = "linux" ]; then
      linux_examples=$((linux_examples + 1))
      is_linux || { skipped_linux=$((skipped_linux + 1)); continue; }
    fi

    # Safety normalization + the deterministic-rc subset.
    local strict=0 had_force=0 has_check=0
    local -a norm=()
    case "${args[0]-}" in
      clean)
        strict=1
        for tok in ${args[@]+"${args[@]}"}; do
          case "$tok" in
            --force|-f) had_force=1 ;;
            *)          norm+=("$tok") ;;
          esac
        done
        if [ "$had_force" -eq 1 ]; then
          args=("${norm[@]}" --dry-run)
        fi
        ;;
      fix)
        envs+=("DRY_RUN=true")
        ;;
      update)
        # A bare `update` applies a self-update for real — there is no
        # --dry-run, so `--check` is its doc-safe form.
        for tok in ${args[@]+"${args[@]}"}; do
          [ "$tok" = "--check" ] && has_check=1
        done
        [ "$has_check" -eq 0 ] && args+=(--check)
        ;;
      info|list|history|version|help|diagnose)
        strict=1
        ;;
    esac

    local out="$TEST_TMP/example-L${lineno}.out" rc=0
    if command -v timeout >/dev/null 2>&1; then
      timeout "$_DOC_CMD_TIMEOUT" env HOME="$TEST_HOME" ${envs[@]+"${envs[@]}"} \
        "$ROOT_DIR/mdoctor" ${args[@]+"${args[@]}"} </dev/null >"$out" 2>&1 || rc=$?
    else
      env HOME="$TEST_HOME" ${envs[@]+"${envs[@]}"} \
        "$ROOT_DIR/mdoctor" ${args[@]+"${args[@]}"} </dev/null >"$out" 2>&1 || rc=$?
    fi
    ran=$((ran + 1))

    if _rejection_seen "$out"; then
      failures="${failures}L${lineno} REJECTED: ${line}\n$(cat "$out")\n---\n"
    elif [ "$strict" -eq 1 ] && [ "$rc" -ne 0 ]; then
      failures="${failures}L${lineno} rc=${rc} (expected 0): ${line}\n$(cat "$out")\n---\n"
    elif [ ! -s "$out" ]; then
      failures="${failures}L${lineno} produced no output: ${line}\n"
    fi
  done < <(_doc_fenced_lines)

  # Extraction sanity + routing coverage in both directions.
  if [ "$ran" -lt 15 ]; then
    failures="${failures}only ${ran} examples executed — fence extraction likely broken\n"
  fi
  if [ "$macos_examples" -lt 1 ] || [ "$linux_examples" -lt 1 ]; then
    failures="${failures}expected >=1 macOS-only and >=1 Linux-only labeled example (got ${macos_examples}/${linux_examples})\n"
  fi
  if is_macos && [ "$skipped_linux" -lt 1 ]; then
    failures="${failures}no Linux-only example was routed away on the macOS lane\n"
  fi
  if is_linux && [ "$skipped_macos" -lt 1 ]; then
    failures="${failures}no macOS-only example was routed away on the Linux lane\n"
  fi

  echo "executed=${ran} macOS-only-examples=${macos_examples}(skipped=${skipped_macos}) Linux-only-examples=${linux_examples}(skipped=${skipped_linux}) templates=${templates}"
  if [ -n "$failures" ]; then
    printf '%b' "$failures" >&2
    fail "guidebook command examples failed or were rejected"
  fi
}
