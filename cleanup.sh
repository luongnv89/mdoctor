#!/usr/bin/env bash
#
# cleanup.sh
# Generic manual cleanup script for macOS with progress + summary.
#
# Default: DRY RUN (shows what would be deleted, nothing actually removed).
# Usage:
#   ./cleanup.sh           # dry run
#   ./cleanup.sh --force   # actually delete
#   ./cleanup.sh --debug   # dry run + structured debug diagnostics
#

set -euo pipefail

########################################
# SCRIPT DIRECTORY & MODULE LOADING
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/disk.sh"
source "${SCRIPT_DIR}/lib/safety.sh"
source "${SCRIPT_DIR}/lib/cleanup_scope.sh"

# Source cleanup modules
source "${SCRIPT_DIR}/cleanups/trash.sh"
source "${SCRIPT_DIR}/cleanups/caches.sh"
source "${SCRIPT_DIR}/cleanups/logs.sh"
source "${SCRIPT_DIR}/cleanups/downloads.sh"
source "${SCRIPT_DIR}/cleanups/browser.sh"
source "${SCRIPT_DIR}/cleanups/dev.sh"
source "${SCRIPT_DIR}/cleanups/crash_reports.sh"
source "${SCRIPT_DIR}/cleanups/ios_backups.sh"
source "${SCRIPT_DIR}/cleanups/xcode.sh"
source "${SCRIPT_DIR}/cleanups/dev_caches.sh"

########################################
# CONFIGURATION
########################################

DRY_RUN=true
LOGFILE="${HOME}/Library/Logs/macos_cleanup.log"
MDOCTOR_DEBUG="${MDOCTOR_DEBUG:-false}"
# shellcheck disable=SC2034
DAYS_OLD="${DAYS_OLD_OVERRIDE:-7}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--force|-f)
			DRY_RUN=false
			shift
			;;
		--debug)
			MDOCTOR_DEBUG=true
			export MDOCTOR_DEBUG
			shift
			;;
		--help|-h)
			echo "Usage: ./cleanup.sh [--force] [--debug]"
			echo
			echo "  --force, -f   Actually delete files (default is dry-run)"
			echo "  --debug       Enable structured debug diagnostics"
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			echo "Usage: ./cleanup.sh [--force] [--debug]" >&2
			exit 1
			;;
	esac
done

########################################
# PROGRESS HANDLING
########################################

PROGRESS_CURRENT=0
PROGRESS_TOTAL=8 # update if you add/remove core steps below

# Alias for progress bar functions (they use STEP_CURRENT/STEP_TOTAL)
# shellcheck disable=SC2034
STEP_CURRENT=0
# shellcheck disable=SC2034
STEP_TOTAL=$PROGRESS_TOTAL

step() {
	progress_stop

	PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
	# shellcheck disable=SC2034
	STEP_CURRENT=$PROGRESS_CURRENT
	local label="$1"
	echo
	echo "➤ [${PROGRESS_CURRENT}/${PROGRESS_TOTAL}] ${label}"

	progress_start "$label"
}

########################################
# OPERATION SESSION LIFECYCLE
########################################

OP_SESSION_ACTIVE=false

_finish_cleanup_session() {
	local rc=$?
	progress_stop || true
	if [ "$OP_SESSION_ACTIVE" = true ] && declare -f op_session_end >/dev/null 2>&1; then
		if [ "$rc" -eq 0 ]; then
			op_session_end "ok"
		else
			op_session_end "error:${rc}"
		fi
	fi
}

trap _finish_cleanup_session EXIT

cleanup_preflight_path_kb() {
	local path="${1-}"
	if [ -z "$path" ] || [ ! -e "$path" ]; then
		echo 0
		return 0
	fi
	du -sk "$path" 2>/dev/null | awk '{print $1+0}'
}

cleanup_preflight_find_kb() {
	local base="${1-}"
	shift || true

	if [ -z "$base" ] || [ ! -d "$base" ]; then
		echo 0
		return 0
	fi

	local total=0
	local p=""
	while IFS= read -r -d '' p; do
		local sz=0
		sz=$(du -sk "$p" 2>/dev/null | awk '{print $1+0}')
		total=$((total + sz))
	done < <(find "$base" "$@" -print0 2>/dev/null)

	echo "$total"
}

cleanup_force_preflight_summary() {
	local days="${DAYS_OLD:-7}"
	local total_kb=0

	echo
	echo "${BOLD:-}${YELLOW:-}== Pre-flight Safety Summary (force mode) ==${RESET:-}"
	echo "Modules touched: trash, caches, logs, downloads, crash_reports, ios_backups, xcode, dev_caches"
	echo "Touched targets:"

	local path sz
	for path in \
		"${HOME}/.Trash" \
		"${HOME}/Library/Caches" \
		"${HOME}/Library/Developer/Xcode/DerivedData" \
		"${HOME}/Library/Developer/CoreSimulator/Caches" \
		"${HOME}/.npm" \
		"${HOME}/.cache/pip" \
		"${HOME}/.m2/repository" \
		"${HOME}/.gradle/caches" \
		"${HOME}/go/pkg/mod/cache" \
		"${HOME}/.cargo/registry/cache"; do
		sz=$(cleanup_preflight_path_kb "$path")
		total_kb=$((total_kb + sz))
		printf "  - %-45s (~%s)\n" "$path" "$(human_readable_kb "$sz")"
	done

	local logs_kb dl_kb crash_user_kb crash_sys_kb ios_kb archives_kb
	logs_kb=$(cleanup_preflight_find_kb "${HOME}/Library/Logs" -type f -mtime "+${days}")
	dl_kb=$(cleanup_preflight_find_kb "${HOME}/Downloads" -type f -size +500M -mtime "+${days}")
	crash_user_kb=$(cleanup_preflight_find_kb "${HOME}/Library/Logs/DiagnosticReports" -type f "(" -name "*.crash" -o -name "*.diag" -o -name "*.ips" ")" -mtime "+${days}")
	crash_sys_kb=$(cleanup_preflight_find_kb "/Library/Logs/DiagnosticReports" -type f "(" -name "*.crash" -o -name "*.diag" -o -name "*.ips" ")" -mtime "+${days}")
	ios_kb=$(cleanup_preflight_find_kb "${HOME}/Library/Application Support/MobileSync/Backup" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}")
	archives_kb=$(cleanup_preflight_find_kb "${HOME}/Library/Developer/Xcode/Archives" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}")

	total_kb=$((total_kb + logs_kb + dl_kb + crash_user_kb + crash_sys_kb + ios_kb + archives_kb))

	printf "  - %-45s (~%s)\n" "${HOME}/Library/Logs (files older than ${days}d)" "$(human_readable_kb "$logs_kb")"
	printf "  - %-45s (~%s)\n" "${HOME}/Downloads (>500MB, older than ${days}d)" "$(human_readable_kb "$dl_kb")"
	printf "  - %-45s (~%s)\n" "${HOME}/Library/Logs/DiagnosticReports" "$(human_readable_kb "$crash_user_kb")"
	printf "  - %-45s (~%s)\n" "/Library/Logs/DiagnosticReports" "$(human_readable_kb "$crash_sys_kb")"
	printf "  - %-45s (~%s)\n" "${HOME}/Library/Application Support/MobileSync/Backup (> ${days}d)" "$(human_readable_kb "$ios_kb")"
	printf "  - %-45s (~%s)\n" "${HOME}/Library/Developer/Xcode/Archives (> ${days}d)" "$(human_readable_kb "$archives_kb")"

	echo "  - docker system prune -af --volumes (size estimate: n/a)"
	echo "  - xcrun simctl delete unavailable (size estimate: n/a)"
	echo
	echo "Estimated reclaim size: ~$(human_readable_kb "$total_kb")"
	echo "${YELLOW:-}Note:${RESET:-} estimate is approximate and excludes dynamic command-based reclaim sizes."
	echo
}

########################################
# MAIN
########################################

main() {
	mkdir -p "$(dirname "$LOGFILE")"
	echo >>"$LOGFILE"

	local used_before_kb
	local used_after_kb
	local freed_kb
	local freed_hr

	used_before_kb="$(disk_used_kb)"

	if declare -f ensure_cleanup_whitelist_file >/dev/null 2>&1; then
		ensure_cleanup_whitelist_file
	fi
	if declare -f ensure_cleanup_scope_file >/dev/null 2>&1; then
		ensure_cleanup_scope_file
	fi

	if [ "$DRY_RUN" = false ]; then
		cleanup_force_preflight_summary
	fi

	header "Starting macOS cleanup (DRY_RUN=${DRY_RUN})"
	debug_log "cleanup.sh start dry_run=${DRY_RUN} days_old=${DAYS_OLD}"
	log "$(disk_usage)"

	# Core generic cleanups – safe-ish for any macOS user
	step "Emptying Trash"
	clean_trash

	step "Cleaning user caches"
	clean_user_caches

	step "Cleaning old logs"
	clean_logs

	step "Scanning large files in Downloads"
	clean_downloads_large_files

	# New cleanup modules
	step "Cleaning crash reports"
	clean_crash_reports

	step "Checking iOS backups"
	clean_ios_backups

	step "Xcode cleanup"
	clean_xcode

	step "Developer caches cleanup"
	clean_dev_caches

	# OPTIONAL: Uncomment if you want these too (and bump PROGRESS_TOTAL)
	# step "Cleaning browser caches"
	# clean_browser_caches
	#
	# step "Developer caches & tools cleanup"
	# clean_dev_stuff

	# Stop spinner from last step
	progress_stop

	if [ "$DRY_RUN" = true ]; then
		used_after_kb="$used_before_kb"
	else
		used_after_kb="$(disk_used_kb)"
	fi

	freed_kb=$((used_before_kb - used_after_kb))
	if ((freed_kb < 0)); then
		freed_kb=0
	fi

	freed_hr="$(human_readable_kb "$freed_kb")"

	log "Cleanup finished."
	log "$(disk_usage)"

	if [ "$DRY_RUN" = true ]; then
		log "Estimated space that COULD be freed: ${freed_hr} (dry run – no actual changes made)."
	else
		log "Estimated space freed: ${freed_hr}."
	fi

	debug_log "cleanup.sh end dry_run=${DRY_RUN} estimated_freed=${freed_hr}"
}

op_session_start "clean:full"
OP_SESSION_ACTIVE=true

main "$@"
