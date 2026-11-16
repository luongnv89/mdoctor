#!/usr/bin/env bash
#
# cleanups/worktrees.sh
# Scan for git worktrees and remove the ones that are safe to delete.
#
# Opt-in only: `mdoctor clean -m worktrees` (dry-run scan, the default) or
# `mdoctor clean -m worktrees --force`. It is deliberately NOT part of the
# engine's full-run CLEANUP_STEPS — a blanket `clean --force` must never
# remove a developer's checkouts.
#
# Discovery: every git repository under the cleanup scope roots
# (lib/cleanup_scope.sh — INCLUDE_PATH lines or the default project dirs)
# is asked for its worktrees with `git worktree list --porcelain`, so a
# worktree living outside the scan roots (../repo-wt, .claude/worktrees/*)
# is still found through its repository.
#
# Deletion never touches the filesystem directly: removal is
# `git worktree remove <path>` WITHOUT --force, so git itself refuses a
# worktree that turned dirty between the scan and the removal, and stale
# admin entries (directory already gone) are cleared with
# `git worktree prune`. The branch a removed worktree had checked out is
# always kept — removing a worktree never deletes commits.
#
# A linked worktree is "safe to delete" only when ALL of these hold:
#   - not the main worktree, not bare, not locked
#   - the current directory is not inside it
#   - not whitelisted (cleanup_whitelist), not scope-excluded, not a
#     protected path
#   - `git status` is clean, untracked files included
#   - no rebase/merge/cherry-pick/revert/bisect in progress
#   - no submodules (git refuses to remove those without --force)
#   - HEAD is reachable from a ref (a detached HEAD with commits no
#     branch/tag/remote contains would orphan them)
#   - every ignored entry is a regenerable artifact (node_modules, .venv,
#     build output, caches…) — ignored files such as .env are lost on
#     removal, so their presence keeps the worktree
#   - no activity in the last DAYS_OLD days (worktree root, its index and
#     HEAD), so a worktree an agent or editor is using right now is kept

# Module context contract (Task 9.1): fail loudly when sourced without the
# initializer instead of running on uncontrolled defaults.
# Required cleanups inputs: DRY_RUN, DAYS_OLD, LOGFILE, STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

# How deep below each scope root to look for repositories.
MDOCTOR_WORKTREE_SCAN_DEPTH="${MDOCTOR_WORKTREE_SCAN_DEPTH:-4}"

# _worktree_days — inactivity threshold in days (module default 7).
_worktree_days() {
  local days="${DAYS_OLD:-7}"
  case "$days" in ''|*[!0-9]*) days=7 ;; esac
  printf '%s' "$days"
}

# _worktree_abs_dir DIR — physical absolute path of DIR (empty on failure).
_worktree_abs_dir() {
  if [ -d "$1" ]; then
    (cd "$1" 2>/dev/null && pwd -P)
  fi
  return 0
}

# _worktree_is_disposable NAME — 0 when an ignored entry is a regenerable
# artifact that may be lost with the worktree.
_worktree_is_disposable() {
  local name="${1%/}"
  name="${name##*/}"
  case "$name" in
    node_modules|.venv|venv|__pycache__|.pytest_cache|.mypy_cache|.ruff_cache|.tox|.nox) return 0 ;;
    dist|build|target|out|.next|.nuxt|.svelte-kit|.turbo|.parcel-cache|.cache|coverage|.coverage|.gradle|.eggs|*.egg-info) return 0 ;;
    .DS_Store|*.pyc|*.pyo|*.log|.idea|.vscode) return 0 ;;
  esac
  return 1
}

# _worktree_repo_dirs — one git common dir (absolute) per repository found
# under the cleanup scope roots, deduplicated.
_worktree_repo_dirs() {
  local root hit parent common abs s
  local -a seen=()
  while IFS= read -r root; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    while IFS= read -r -d '' hit; do
      parent="${hit%/.git}"
      common="$(git -C "$parent" rev-parse --git-common-dir 2>/dev/null)" || continue
      [ -n "$common" ] || continue
      case "$common" in
        /*) abs="$(_worktree_abs_dir "$common")" ;;
        *) abs="$(_worktree_abs_dir "${parent}/${common}")" ;;
      esac
      [ -n "$abs" ] || continue
      for s in ${seen[@]+"${seen[@]}"}; do
        [ "$s" = "$abs" ] && continue 2
      done
      seen+=("$abs")
      printf '%s\n' "$abs"
    done < <(find "$root" -maxdepth "$MDOCTOR_WORKTREE_SCAN_DEPTH" \
      \( -name node_modules -o -name .venv -o -name venv \) -prune \
      -o -name .git -print0 -prune 2>/dev/null)
  done < <(cleanup_scope_get_search_dirs)
}

# _worktree_keep_reason PATH HEAD DETACHED COMMON — prints why the linked
# worktree at PATH must be kept; prints nothing when it is safe to remove.
_worktree_keep_reason() {
  local wt="$1" head="$2" detached="$3" common="$4"
  local days here gitdir status entry

  here="$(pwd -P 2>/dev/null)" || here=""
  if [ -n "$here" ] && { [ "$here" = "$wt" ] || [[ "$here" == "$wt/"* ]]; }; then
    echo "current directory is inside it"; return 0
  fi
  if is_protected_deletion_path "$wt"; then
    echo "protected path"; return 0
  fi
  if is_whitelisted_cleanup_path "$wt"; then
    echo "whitelisted"; return 0
  fi
  if cleanup_scope_is_excluded "$wt"; then
    echo "excluded by cleanup scope"; return 0
  fi

  gitdir="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" || gitdir=""
  if [ -z "$gitdir" ]; then
    echo "git dir not found"; return 0
  fi

  # Activity is measured BEFORE git status runs: status may refresh the
  # index and would otherwise make every worktree look freshly used.
  days="$(_worktree_days)"
  if [ "$days" -gt 0 ]; then
    if [ -n "$(find "$wt" -maxdepth 0 -mtime "-${days}" 2>/dev/null)" ] ||
       [ -n "$(find "$gitdir" -maxdepth 1 \( -name index -o -name HEAD \) -mtime "-${days}" 2>/dev/null)" ]; then
      echo "active within the last ${days} days"; return 0
    fi
  fi

  # --no-optional-locks: the scan itself must not rewrite the index.
  if ! status="$(git --no-optional-locks -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)"; then
    echo "git status failed"; return 0
  fi
  if [ -n "$status" ]; then
    echo "uncommitted or untracked changes"; return 0
  fi
  for entry in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    if [ -e "${gitdir}/${entry}" ]; then
      echo "operation in progress (${entry})"; return 0
    fi
  done

  if [ -f "${wt}/.gitmodules" ]; then
    echo "contains submodules"; return 0
  fi

  if [ "$detached" = true ] && [ -n "$head" ]; then
    if [ -z "$(git --git-dir="$common" for-each-ref --contains "$head" --count=1 2>/dev/null)" ]; then
      echo "detached HEAD has commits no branch, tag or remote contains"; return 0
    fi
  fi

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if ! _worktree_is_disposable "$entry"; then
      echo "ignored files would be lost (${entry})"; return 0
    fi
  done < <(git --no-optional-locks -C "$wt" ls-files --others --ignored --exclude-standard --directory 2>/dev/null)

  return 0
}

# worktree_scan_candidates — evaluate every linked worktree. One line per
# worktree, tab-separated: ACTION COMMON_DIR PATH LABEL REASON, where
# ACTION is remove | prune | keep. Shared by the module and the force-mode
# pre-flight summary in mdoctor.
worktree_scan_candidates() {
  command -v git >/dev/null 2>&1 || return 0
  local common line wt head branch detached locked prunable first label reason

  _wt_emit() {
    [ -n "$wt" ] || return 0
    if [ "$first" = true ]; then
      first=false
      return 0
    fi
    if [ "$detached" = true ]; then
      label="detached ${head:0:7}"
    else
      label="${branch:-bare}"
    fi
    if [ "$prunable" = true ] || [ ! -d "$wt" ]; then
      if [ "$locked" = true ]; then
        printf 'keep\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "locked (directory missing)"
      else
        printf 'prune\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "directory no longer exists"
      fi
      return 0
    fi
    if [ "$locked" = true ]; then
      printf 'keep\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "locked"
      return 0
    fi
    if [ -z "$branch" ] && [ "$detached" != true ]; then
      printf 'keep\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "bare entry"
      return 0
    fi
    reason="$(_worktree_keep_reason "$wt" "$head" "$detached" "$common")"
    if [ -n "$reason" ]; then
      printf 'keep\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "$reason"
    else
      printf 'remove\t%s\t%s\t%s\t%s\n' "$common" "$wt" "$label" "clean and inactive"
    fi
  }

  while IFS= read -r common; do
    [ -z "$common" ] && continue
    wt="" head="" branch="" detached=false locked=false prunable=false first=true
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "worktree "*)
          _wt_emit
          wt="${line#worktree }" head="" branch="" detached=false locked=false prunable=false
          ;;
        "HEAD "*) head="${line#HEAD }" ;;
        "branch "*) branch="${line#branch refs/heads/}" ;;
        detached) detached=true ;;
        locked|"locked "*) locked=true ;;
        prunable|"prunable "*) prunable=true ;;
      esac
    done < <(git --git-dir="$common" worktree list --porcelain 2>/dev/null)
    _wt_emit
  done < <(_worktree_repo_dirs)
  unset -f _wt_emit
}

clean_git_worktrees() {
  local rc=0 days
  days="$(_worktree_days)"
  header "Scanning git worktrees (safe to delete: clean, inactive >${days} days)"

  if ! command -v git >/dev/null 2>&1; then
    log "git not found; skipping worktree scan."
    return 0
  fi

  local action common wt label reason disp
  local n_remove=0 n_prune=0 n_keep=0
  local -a pruned=()
  local p
  while IFS=$'\t' read -r action common wt label reason; do
    [ -z "$action" ] && continue
    disp="$wt"
    # shellcheck disable=SC2088 # literal ~ is the intended display prefix
    case "$wt" in "${HOME}/"*) disp="~/${wt#"${HOME}"/}" ;; esac
    case "$action" in
      remove)
        log "Safe to remove: ${disp} [${label}] — ${reason}"
        if run_cmd_args git --git-dir="$common" worktree remove "$wt"; then
          n_remove=$((n_remove + 1))
        else
          rc="$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE"
        fi
        ;;
      prune)
        log "Stale entry: ${disp} [${label}] — ${reason}"
        n_prune=$((n_prune + 1))
        for p in ${pruned[@]+"${pruned[@]}"}; do
          [ "$p" = "$common" ] && continue 2
        done
        pruned+=("$common")
        run_cmd_args git --git-dir="$common" worktree prune || rc="$MDOCTOR_SAFE_ERR_RUNTIME_FAILURE"
        ;;
      keep)
        log "Keeping: ${disp} [${label}] — ${reason}"
        n_keep=$((n_keep + 1))
        ;;
    esac
  done < <(worktree_scan_candidates)

  if [ $((n_remove + n_prune + n_keep)) -eq 0 ]; then
    log "No linked git worktrees found under the cleanup scope roots."
  else
    log "Worktrees: ${n_remove} removable, ${n_prune} stale entries, ${n_keep} kept. Branches are never deleted."
  fi

  rc="$(handle_cleanup_rc "$rc")"
  [ "$rc" -eq 0 ] || log "Module 'worktrees' finished with $(safety_error_name "$rc"): $(safety_error_hint "$rc" 'worktrees')"
  return "$rc"
}
