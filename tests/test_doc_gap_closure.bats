#!/usr/bin/env bats
#
# test_doc_gap_closure.bats — issue #120 (task 13.7)
#
# Pins the documentation invariants closed by the small-gaps pass:
#
# 1. Global options — README's "Global Options" section names --debug +
#    MDOCTOR_DEBUG, `update --channel` + MDOCTOR_CHANNEL, and the short
#    version aliases. The --debug "accepted by" command set is derived
#    from which cmd_* bodies call parse_common_args, and the aliases
#    from main()'s dispatch arms — the doc cannot drift from the code.
#    GUIDEBOOK's Tips block also names the debug flag.
#
# 2. Installer variables — every MDOCTOR_* token install.sh and
#    uninstall.sh consume appears in DEPLOYMENT.md's Installer
#    Environment Variables table (derived from the scripts, not a hand
#    list); README links the table from both the Configuration and
#    Uninstall sections; DEPLOYMENT's Uninstalling section tells a
#    custom-prefix user which variables to re-declare.
#
# 3. Bug template — the Environment block covers both platforms (OS,
#    OS version, a Linux distro line, architecture, mdoctor version,
#    shell) and the template asks for `mdoctor info` output.
#
# 4. SECURITY.md — states the tag-based supported range the installer's
#    tag pinning makes meaningful, and carries a Threat Model section
#    naming the privileged/destructive surfaces.
#
# 5. DEVELOPMENT.md — no hand-maintained coverage enumeration; it
#    points at tests/test_*.bats instead.
#
# Read-only: asserts on repository files, touches nothing.

load 'helpers/assert'

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export ROOT_DIR
README="$ROOT_DIR/README.md"
DEPLOYMENT="$ROOT_DIR/docs/DEPLOYMENT.md"
GUIDEBOOK="$ROOT_DIR/docs/GUIDEBOOK.md"
DEVELOPMENT="$ROOT_DIR/docs/DEVELOPMENT.md"
SECURITY="$ROOT_DIR/SECURITY.md"
BUG_TEMPLATE="$ROOT_DIR/.github/ISSUE_TEMPLATE/bug_report.md"
MDOCTOR="$ROOT_DIR/mdoctor"
INSTALLER="$ROOT_DIR/install.sh"
UNINSTALLER="$ROOT_DIR/uninstall.sh"

# Section slicers — each prints the markdown section under test, from
# its heading to the next heading at the same level (sed range ends are
# tested on lines after the start, so a generic end anchor is safe).
_global_options()   { sed -n '/^### Global Options/,/^### /p' "$README"; }
_readme_config()    { sed -n '/^## Configuration/,/^## /p' "$README"; }
_readme_uninstall() { sed -n '/^## Uninstall/,/^## /p' "$README"; }
_installer_table()  { sed -n '/^## Installer Environment Variables/,/^## /p' "$DEPLOYMENT"; }
_deploy_uninstall() { sed -n '/^## Uninstalling/,/^## /p' "$DEPLOYMENT"; }
_guidebook_tips()   { sed -n '/^## Tips/,$p' "$GUIDEBOOK"; }
_template_env()     { sed -n '/^## Environment/,/^## /p' "$BUG_TEMPLATE"; }
_threat_model()     { sed -n '/^## Threat Model/,/^## /p' "$SECURITY"; }

@test "README Global Options names the debug flag and its variable" {
	local section
	section="$(_global_options)"
	[ -n "$section" ] || fail "README has no '### Global Options' section"
	printf '%s\n' "$section" | grep -qF -- '--debug' \
		|| fail "Global Options does not document --debug"
	printf '%s\n' "$section" | grep -qF 'MDOCTOR_DEBUG' \
		|| fail "Global Options does not name MDOCTOR_DEBUG"
}

@test "Global Options lists every command that parses common flags" {
	# Derived: each usage_* passed to parse_common_args names a command
	# whose parser accepts --debug/-h. The doc column must cover them.
	local cmds cmd section
	cmds="$(grep -oE 'parse_common_args usage_[a-z_]+' "$MDOCTOR" \
		| sed 's/.*usage_//' | sort -u)"
	[ -n "$cmds" ] || fail "no parse_common_args call sites found in mdoctor"
	section="$(_global_options)"
	for cmd in $cmds; do
		printf '%s\n' "$section" | grep -qF "\`$cmd\`" \
			|| fail "Global Options omits '${cmd}' — it accepts --debug via parse_common_args"
	done
}

@test "Global Options documents the update channel and version aliases" {
	local section
	section="$(_global_options)"
	printf '%s\n' "$section" | grep -qF -- '--channel' \
		|| fail "Global Options does not document update --channel"
	printf '%s\n' "$section" | grep -qF 'MDOCTOR_CHANNEL' \
		|| fail "Global Options does not name MDOCTOR_CHANNEL"
	# The aliases documented must be the ones main() dispatches on.
	grep -qF 'version)' "$MDOCTOR" \
		|| fail "main() lost the 'version' dispatch arm"
	grep -qF -- '-v|--version)' "$MDOCTOR" \
		|| fail "main() lost the '-v|--version' dispatch arm"
	printf '%s\n' "$section" | grep -qF 'mdoctor version' \
		|| fail "Global Options does not document 'mdoctor version'"
	printf '%s\n' "$section" | grep -qF 'mdoctor -v' \
		|| fail "Global Options does not document the -v alias"
	printf '%s\n' "$section" | grep -qF 'mdoctor --version' \
		|| fail "Global Options does not document the --version alias"
}

@test "GUIDEBOOK tips block names the debug flag and its variable" {
	local section
	section="$(_guidebook_tips)"
	[ -n "$section" ] || fail "GUIDEBOOK has no '## Tips' block"
	printf '%s\n' "$section" | grep -qF -- '--debug' \
		|| fail "GUIDEBOOK Tips block does not mention --debug"
	printf '%s\n' "$section" | grep -qF 'MDOCTOR_DEBUG' \
		|| fail "GUIDEBOOK Tips block does not name MDOCTOR_DEBUG"
}

@test "DEPLOYMENT installer table names every MDOCTOR_ var the scripts read" {
	local vars var missing="" n
	vars="$(grep -ohE 'MDOCTOR_[A-Z_]+' "$INSTALLER" "$UNINSTALLER" | sort -u)"
	[ -n "$vars" ] || fail "no MDOCTOR_ variables found in install.sh/uninstall.sh"
	for var in $vars; do
		_installer_table | grep -qF "$var" || missing="${missing}${var} "
	done
	[ -z "$missing" ] \
		|| fail "DEPLOYMENT installer table omits script-read variables: $missing"
	# The issue's counted surface: at least six MDOCTOR_ lines.
	n="$(grep -c 'MDOCTOR_' "$DEPLOYMENT")"
	[ "$n" -ge 6 ] || fail "DEPLOYMENT.md carries only $n MDOCTOR_ lines (<6)"
}

@test "DEPLOYMENT tells custom-prefix users what the uninstaller removes" {
	local section
	section="$(_deploy_uninstall)"
	[ -n "$section" ] || fail "DEPLOYMENT has no '## Uninstalling' section"
	printf '%s\n' "$section" | grep -qF 'MDOCTOR_INSTALL_DIR' \
		|| fail "Uninstalling section does not name MDOCTOR_INSTALL_DIR"
	printf '%s\n' "$section" | grep -qF 'MDOCTOR_BIN_LINK' \
		|| fail "Uninstalling section does not name MDOCTOR_BIN_LINK"
	printf '%s\n' "$section" | grep -qF '#installer-environment-variables' \
		|| fail "Uninstalling section does not cross-link the env-var table"
}

@test "README links the installer table from Configuration and Uninstall" {
	local anchor='DEPLOYMENT.md#installer-environment-variables'
	_readme_config | grep -qF "$anchor" \
		|| fail "README Configuration section does not link the installer table"
	_readme_uninstall | grep -qF "$anchor" \
		|| fail "README Uninstall section does not link the installer table"
}

@test "bug report template covers both platforms and asks for mdoctor info" {
	local env_block
	env_block="$(_template_env)"
	[ -n "$env_block" ] || fail "bug template has no '## Environment' section"
	printf '%s\n' "$env_block" | grep -qi 'macOS' \
		|| fail "Environment block lost the macOS coverage"
	printf '%s\n' "$env_block" | grep -qi 'Linux' \
		|| fail "Environment block has no Linux coverage"
	printf '%s\n' "$env_block" | grep -qi 'distro' \
		|| fail "Environment block has no distribution line"
	printf '%s\n' "$env_block" | grep -qi 'architecture' \
		|| fail "Environment block lost the architecture line"
	printf '%s\n' "$env_block" | grep -qi 'mdoctor version' \
		|| fail "Environment block lost the mdoctor version line"
	printf '%s\n' "$env_block" | grep -qi 'shell' \
		|| fail "Environment block lost the shell line"
	grep -qF 'mdoctor info' "$BUG_TEMPLATE" \
		|| fail "bug template does not ask for mdoctor info output"
}

@test "SECURITY.md states the tag range the installer pins" {
	# The doc claim is only meaningful while the code pins tags — pin
	# both sides so a mechanism change forces a doc re-check.
	grep -q 'latest_release_tag' "$INSTALLER" \
		|| fail "install.sh no longer pins a release tag"
	grep -q 'mdoctor_latest_tag' "$MDOCTOR" \
		|| fail "mdoctor update no longer pins a release tag"
	grep -q 'vX.Y.Z' "$SECURITY" \
		|| fail "SECURITY.md does not state a vX.Y.Z tag-based range"
	grep -qi 'latest' "$SECURITY" \
		|| fail "SECURITY.md does not state the latest-tag policy"
	grep -q ':white_check_mark:' "$SECURITY" \
		|| fail "supported-versions table lost its supported row"
	grep -q ':x:' "$SECURITY" \
		|| fail "supported-versions table lost its unsupported row"
}

@test "SECURITY.md threat model names the privileged and destructive surfaces" {
	local section kw missing=""
	section="$(_threat_model)"
	[ -n "$section" ] || fail "SECURITY.md has no '## Threat Model' section"
	for kw in 'safety.sh' '--force' '/usr/local/bin' 'update' 'sudo' 'PATH' 'timeout'; do
		printf '%s\n' "$section" | grep -qF -- "$kw" || missing="${missing}${kw} "
	done
	[ -z "$missing" ] || fail "Threat Model omits surfaces: $missing"
	printf '%s\n' "$section" | grep -qF 'SAFETY.md' \
		|| fail "Threat Model does not reference the canonical safety doc"
}

@test "DEVELOPMENT.md points at the live test list, not a stale enumeration" {
	grep -qF 'tests/test_*.bats' "$DEVELOPMENT" \
		|| fail "DEVELOPMENT.md does not point at tests/test_*.bats"
	if grep -q 'Current coverage includes' "$DEVELOPMENT"; then
		fail "DEVELOPMENT.md still carries the hand-maintained coverage list"
	fi
}
