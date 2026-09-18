#!/usr/bin/env bats
#
# test_doc_counts.bats — issue #115 (task 13.2)
#
# Docs must never carry hand-maintained module counts again. This file
# enforces three things over README.md and docs/:
#
# 1. The retired literals are gone: `21 checks`, `10 modules`,
#    `9 targets` — the exact grep from the issue's acceptance criteria.
#
# 2. Every surviving count claim matches a derived reference. Docs use
#    two spellings, both machine-checked:
#      * per-platform pair  — "N on macOS / M on Linux" (one claim per
#        source line; the line's keywords pick the counter it is
#        compared against)
#      * file inventory     — "(N files)" next to a `dir/` token,
#        verified against the real directory listing
#    A bare "N checks|modules|targets|fixes" claim with no platform
#    qualifier and no `mdoctor list` pointer fails outright: counts are
#    platform-dependent, so a single number is always wrong somewhere.
#
#    Classification (first hit wins): "files" → directory inventory;
#    "full*clean"/"step list" → cleanup.sh CLEANUP_STEPS; "fix"/
#    "target" → fix targets; "diagnos" → diagnose; "check" → checks;
#    "clean"/"module" → cleanup modules.
#
#    References: `mdoctor list` headers for the running lane, plus a
#    predicate-stubbed register_all_modules() for both lanes (the
#    registry is the single source of truth — Task 8.1/8.4), and the
#    CLEANUP_STEPS block in cleanup.sh for the full-clean step list.
#
# 3. Inventories stay complete: every checks/*.sh file appears in the
#    README project-structure tree (label and entries agree), and every
#    docs/*.md + root *.md file is linked in the Documentation index.

load 'helpers/assert'
load 'helpers/fixture'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR

source "$ROOT_DIR/lib/platform.sh"

# _registry_counts LANE — LANE is `macos` or `linux`; prints
# "check cleanup fix diagnose" totals by stubbing the platform
# predicates before register_all_modules runs, so both lanes are
# derivable on either host.
_registry_counts() {
	(
		# Reset guards so the registry re-sources with the stubbed predicates
		# rather than hitting the inherited loaded flag from the parent shell.
		unset _MDOCTOR_METADATA_LOADED _MDOCTOR_REGISTRY_LOADED _MDOCTOR_MODULES_REGISTERED
		if [ "$1" = "macos" ]; then
			is_macos() { return 0; }
			is_linux() { return 1; }
			is_debian() { return 1; }
			is_arch() { return 1; }
			is_omarchy() { return 1; }
		else
			is_macos() { return 1; }
			is_linux() { return 0; }
			is_debian() { return 0; }
			is_arch() { return 1; }
			is_omarchy() { return 1; }
		fi
		source "$ROOT_DIR/lib/metadata.sh"
		source "$ROOT_DIR/lib/registry.sh"
		register_all_modules
		printf '%s %s %s %s\n' \
			"$_REG_COUNT_CHECK" "$_REG_COUNT_CLEANUP" \
			"$_REG_COUNT_FIX" "$_REG_COUNT_DIAGNOSE"
	)
}

# _list_counts — the four `./mdoctor list` header counts for the running
# lane, same field order as _registry_counts. Runs under the fixture
# HOME so the suite stays hermetic.
_list_counts() {
	local out
	out="$(HOME="$TEST_HOME" "$ROOT_DIR/mdoctor" list 2>&1)"
	printf '%s %s %s %s\n' \
		"$(printf '%s\n' "$out" | sed -n 's/^Check Modules (\([0-9][0-9]*\).*/\1/p')" \
		"$(printf '%s\n' "$out" | sed -n 's/^Cleanup Modules (\([0-9][0-9]*\).*/\1/p')" \
		"$(printf '%s\n' "$out" | sed -n 's/^Fix Targets (\([0-9][0-9]*\).*/\1/p')" \
		"$(printf '%s\n' "$out" | sed -n 's/^Diagnose Modules (\([0-9][0-9]*\).*/\1/p')"
}

# _progress_pair — "macOS_total Linux_total" for the full-clean step
# list. cleanup.sh derives STEP_TOTAL from the CLEANUP_STEPS array
# (issue #89), so the pair is computed by evaluating that assignment
# block under each stubbed lane rather than grepping a literal.
_progress_pair() {
	local block mac lin
	block="$(sed -n '/^CLEANUP_STEPS=(/,/^export STEP_TOTAL=/p' "$ROOT_DIR/cleanup.sh" | grep -v '^export ')"
	[ -n "$block" ] || return 1
	mac="$(
		is_macos() { return 0; }
		is_linux() { return 1; }
		is_debian() { return 1; }
		is_arch() { return 1; }
		is_omarchy() { return 1; }
		eval "$block"
		printf '%s' "${#CLEANUP_STEPS[@]}"
	)"
	lin="$(
		is_macos() { return 1; }
		is_linux() { return 0; }
		is_debian() { return 0; }
		is_arch() { return 1; }
		is_omarchy() { return 1; }
		eval "$block"
		printf '%s' "${#CLEANUP_STEPS[@]}"
	)"
	printf '%s %s\n' "$mac" "$lin"
}

# _doc_claim_lines — "file:lineno:text" for every line in README.md and
# docs/ carrying a count claim (per-platform pair, "N files" inventory
# note, or a bare "N checks|modules|targets|fixes"). A platform phrase
# only counts as a claim when a number sits at most one word away from
# it ("20 checks on macOS", "7 on Linux") — prose like "the 3.2 path
# executes only on macOS" is not a count claim. The bare-claim pattern
# requires a non-digit, non-dot, non-letter before the number so task
# labels like "P6.2 check modules" never match.
_doc_claim_lines() {
	grep -nE '[0-9]+([[:space:]]+[a-z]+)?[[:space:]]+on (macOS|Linux)|(^|[^.0-9A-Za-z])[0-9]+[[:space:]]+(checks?|modules?|targets?|fixes)\b|[0-9]+[[:space:]]+files\b' \
		"$ROOT_DIR/README.md" "$ROOT_DIR"/docs/*.md || true
}

# _platform_nums LINE — "N M": the number nearest before "on macOS" and
# the one nearest before "on macOS"'s twin "on Linux". A leading space
# covers numbers at column 0.
_platform_nums() {
	local padded=" $1"
	printf '%s %s\n' \
		"$(printf '%s\n' "$padded" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)[^0-9]*on macOS.*/\1/p')" \
		"$(printf '%s\n' "$padded" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)[^0-9]*on Linux.*/\1/p')"
}

# _expected_pair LINE — prints the reference "macOS Linux" pair for the
# counter this line talks about, or the inventory/progress verdicts.
# Uses the stubbed registry so both lanes are checked wherever we run.
_expected_pair() {
	local line="$1" mac lin dir want
	case "$line" in
		*[0-9]" files"*)
			dir="$(printf '%s\n' "$line" | sed -n 's/.*\b\([a-z_][a-z0-9_]*\)\/.*/\1/p')"
			[ -n "$dir" ] || { printf 'SKIP no-dir\n'; return; }
			[ -d "$ROOT_DIR/$dir" ] || { printf 'BAD missing dir %s\n' "$dir"; return; }
			want="$(find "$ROOT_DIR/$dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')"
			printf 'FILES %s %s\n' "$want" "$dir"
			return
			;;
	esac
	mac="$(_registry_counts macos)"   # "check cleanup fix diagnose"
	lin="$(_registry_counts linux)"
	case "$line" in
		*fix*|*target*)
			printf '%s %s\n' "$(printf '%s' "$mac" | awk '{print $3}')" "$(printf '%s' "$lin" | awk '{print $3}')"
			;;
		*diagnos*)
			printf '%s %s\n' "$(printf '%s' "$mac" | awk '{print $4}')" "$(printf '%s' "$lin" | awk '{print $4}')"
			;;
		*check*)
			printf '%s %s\n' "$(printf '%s' "$mac" | awk '{print $1}')" "$(printf '%s' "$lin" | awk '{print $1}')"
			;;
		*clean*|*module*)
			printf '%s %s\n' "$(printf '%s' "$mac" | awk '{print $2}')" "$(printf '%s' "$lin" | awk '{print $2}')"
			;;
		*)
			printf 'UNCLASSIFIED\n'
			;;
	esac
}

setup_file() {
	cd "$ROOT_DIR" || return 1
	FIXTURE_ROOT="$(fixture_root)"
	export FIXTURE_ROOT
	TEST_TMP="$(mktemp -d "$FIXTURE_ROOT/mdoctor-test-doccounts.$(fixture_run_id).XXXXXX")"
	export TEST_TMP
	fixture_trap_cleanup "$TEST_TMP"
	TEST_HOME="$TEST_TMP/home"
	mkdir -p "$TEST_HOME"
	export TEST_HOME
}

teardown_file() {
	rm -rf "$TEST_TMP"
}

@test "no retired count literals remain in README.md or docs/" {
	local f hits=""
	for f in "$ROOT_DIR/README.md" "$ROOT_DIR"/docs/*.md; do
		local n
		n="$(grep -c '21 checks\|10 modules\|9 targets' "$f" || true)"
		[ "$n" -eq 0 ] || hits="${hits}${f}: ${n} hit(s)\n"
	done
	if [ -n "$hits" ]; then
		printf '%b' "$hits" >&2
		fail "retired literals (21 checks / 10 modules / 9 targets) still in docs"
	fi
}

@test "mdoctor list headers equal the registry on this lane" {
	local listed expected lane
	if is_macos; then lane=macos; else lane=linux; fi
	listed="$(_list_counts)"
	# Derive expected counts from the actual host's platform so the
	# comparison is fair on any distro (Debian, Arch, or other).
	expected="$(
		(
			unset _MDOCTOR_METADATA_LOADED _MDOCTOR_REGISTRY_LOADED _MDOCTOR_MODULES_REGISTERED
			# Inherit the actual host predicates so the registry
			# matches what `mdoctor list` shows on this host.
			source "$ROOT_DIR/lib/metadata.sh"
			source "$ROOT_DIR/lib/registry.sh"
			register_all_modules
			printf '%s %s %s %s\n' \
				"$_REG_COUNT_CHECK" "$_REG_COUNT_CLEANUP" \
				"$_REG_COUNT_FIX" "$_REG_COUNT_DIAGNOSE"
		)
	)"
	[ "$listed" = "$expected" ] || {
		printf 'mdoctor list: %s\nregistry(%s): %s\n' "$listed" "$lane" "$expected" >&2
		fail "mdoctor list diverged from the registry"
	}
}

@test "every doc count claim matches the registry or the file system" {
	local failures="" ref file_lineno line
	while IFS= read -r file_lineno; do
		line="${file_lineno#*:}"        # strip file:
		line="${line#*:}"               # strip lineno:
		case "$line" in
			*"on macOS"*|*"on Linux"*)
				local got_pair want_pair gmac glin
				got_pair="$(_platform_nums "$line")"
				gmac="${got_pair%% *}"
				glin="${got_pair##* }"
				if [ -z "$gmac" ] || [ -z "$glin" ]; then
					failures="${failures}${file_lineno} — unparseable platform pair: ${line}\n"
					continue
				fi
				case "$line" in
					*full*clean*|*"step list"*)
						want_pair="$(_progress_pair)"
						;;
					*)
						want_pair="$(_expected_pair "$line")"
						;;
				esac
				if [ "$got_pair" != "$want_pair" ]; then
					failures="${failures}${file_lineno}\n  doc says '${got_pair}' expected '${want_pair}'\n"
				fi
				;;
			*files*)
				local verdict
				verdict="$(_expected_pair "$line")"
				case "$verdict" in
					SKIP*) ;;
					BAD*)  failures="${failures}${file_lineno} — ${verdict}\n" ;;
					FILES*)
						local want dir got
						want="$(printf '%s' "$verdict" | awk '{print $2}')"
						dir="$(printf '%s' "$verdict" | awk '{print $3}')"
						got="$(printf ' %s\n' "$line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)[^0-9]*files.*/\1/p')"
						[ "$got" = "$want" ] || failures="${failures}${file_lineno} — ${dir}/ holds ${want} files, doc says ${got}\n"
						;;
				esac
				;;
			*)
				# Bare "N checks/modules/targets/fixes" with no platform
				# qualifier — always wrong on one lane.
				failures="${failures}${file_lineno} — bare count claim; make it per-platform or point to mdoctor list\n"
				;;
		esac
	done < <(_doc_claim_lines)
	if [ -n "$failures" ]; then
		printf '%b' "$failures" >&2
		fail "doc counts disagree with the registry-derived truth"
	fi
}

@test "README and GUIDEBOOK state the full-clean step counts and the -m opt-in" {
	local pair
	pair="$(_progress_pair)"
	[ -n "$pair" ] || fail "could not derive CLEANUP_STEPS from cleanup.sh"
	for doc in "$ROOT_DIR/README.md" "$ROOT_DIR/docs/GUIDEBOOK.md"; do
		grep -q 'on macOS / .*on Linux' "$doc" \
			|| fail "$doc lacks a per-platform count pair"
		grep -Eq 'full.{0,24}clean|step list' "$doc" \
			|| fail "$doc does not describe the full-clean step list"
		grep -q 'clean -m\|clean --interactive' "$doc" \
			|| fail "$doc does not point opted-out modules at -m/--interactive"
	done
}

@test "project-structure tree lists every checks/ file and labels it correctly" {
	local tree f base missing=""
	tree="$(sed -n '/^## Project Structure/,/^## Documentation/p' "$ROOT_DIR/README.md")"
	[ -n "$tree" ] || fail "no Project Structure section in README.md"
	for f in "$ROOT_DIR"/checks/*.sh; do
		base="${f##*/}"
		case "$tree" in
			*"$base"*) ;;
			*) missing="${missing}${base} " ;;
		esac
	done
	[ -z "$missing" ] || fail "checks/ files missing from the tree: $missing"
	local label want
	want="$(find "$ROOT_DIR/checks" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')"
	label="$(printf '%s\n' "$tree" | sed -n 's/.*checks\/.*(\([0-9][0-9]*\) files).*/\1/p')"
	[ "$label" = "$want" ] || fail "checks/ label says '${label}' but ${want} files exist"
}

@test "documentation index links every docs/ and root markdown file" {
	local index f base missing=""
	index="$(sed -n '/^## Documentation/,/^## Contributing/p' "$ROOT_DIR/README.md")"
	[ -n "$index" ] || fail "no Documentation section in README.md"
	for f in "$ROOT_DIR"/docs/*.md "$ROOT_DIR"/*.md; do
		base="${f##*/}"
		case "$index" in
			*"$base"*) ;;
			*) missing="${missing}${base} " ;;
		esac
	done
	[ -z "$missing" ] || fail "documents missing from the index: $missing"
}
