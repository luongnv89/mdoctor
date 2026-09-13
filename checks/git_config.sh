#!/usr/bin/env bash
#
# checks/git_config.sh
# Git & SSH configuration audit (read-only, SAFE)
# Category: Software
#


# Module context contract (Task 9.1): the 11 globals this module reads are
# declared by mdoctor_context_init in lib/context.sh. Fail loudly when a
# caller sources this file without the initializer instead of running on
# uncontrolled defaults.
# Required checks inputs: STEP_CURRENT, STEP_TOTAL, MDOCTOR_DEBUG, ACTIONS, WARN_COUNT, FAIL_COUNT, LOG_PATHS, LOG_DESCS, LOGFILE.
if [ "${_MDOCTOR_CONTEXT_READY:-false}" != true ]; then
  echo "${BASH_SOURCE[0]##*/}: module context not initialized (_MDOCTOR_CONTEXT_READY) — call mdoctor_context_init from lib/context.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
check_git_config() {
  step "Git & SSH Configuration"

  # Git availability — platform-correct install advice (issue #109):
  # the Xcode CLT installer exists only on macOS; Linux installs via the
  # package manager (same pattern as checks/devtools.sh).
  if ! command -v git >/dev/null 2>&1; then
    status_warn "Git is not installed."
    if is_macos; then
      add_action "Install Git: xcode-select --install"
    elif is_debian; then
      add_action "Install Git: sudo apt install git"
    else
      add_action "Install Git with your distribution's package manager (e.g. dnf install git, pacman -S git)."
    fi
    return 0
  fi

  status_ok "Git: $(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "unknown" git --version)"   # timeout-capped probe

  # Git user.name
  local git_name
  git_name=$(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "" git config --global user.name)   # timeout-capped probe
  if [ -n "$git_name" ]; then
    status_ok "Git user.name: ${git_name}"
  else
    status_warn "Git user.name is not set globally."
    add_action "Set Git name: git config --global user.name 'Your Name'"
  fi

  # Git user.email
  local git_email
  git_email=$(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "" git config --global user.email)   # timeout-capped probe
  if [ -n "$git_email" ]; then
    status_ok "Git user.email: ${git_email}"
  else
    status_warn "Git user.email is not set globally."
    add_action "Set Git email: git config --global user.email 'you@example.com'"
  fi

  # Git credential helper
  local cred_helper
  cred_helper=$(tcap_or "$MDOCTOR_CMD_TIMEOUT_S" "" git config --global credential.helper)   # timeout-capped probe
  if [ -n "$cred_helper" ]; then
    status_ok "Git credential helper: ${cred_helper}"
  else
    status_info "Git credential helper: not configured"
  fi

  # SSH key existence
  local ssh_dir="${HOME}/.ssh"
  if [ -d "$ssh_dir" ]; then
    local key_count=0
    local f
    for f in "${ssh_dir}"/id_*; do
      [ -f "$f" ] || continue
      # Skip .pub files
      case "$f" in *.pub) continue ;; esac
      key_count=$((key_count + 1))

      # Check permissions (should be 600 or 400)
      local perms
      # stat format differs per platform (macOS -f is meaningless on Linux)
      if is_macos; then
        perms=$(stat -f "%Lp" "$f" 2>/dev/null || echo "")
      else
        perms=$(stat -c "%a" "$f" 2>/dev/null || echo "")
      fi
      if [ -n "$perms" ]; then
        if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
          status_ok "SSH key $(basename "$f"): permissions ${perms} (secure)"
        else
          status_warn "SSH key $(basename "$f"): permissions ${perms} (should be 600 or 400)"
          add_action "Fix SSH key permissions: chmod 600 ${f}"
        fi
      fi
    done

    if (( key_count > 0 )); then
      status_ok "SSH keys found: ${key_count}"
    else
      status_info "No SSH private keys found in ~/.ssh/"
    fi
  else
    status_info "No ~/.ssh directory found."
  fi

  # SSH agent status — substring tests in-shell, no echo|grep (issue #98).
  # ssh-add talks to the agent over a socket and is timeout-capped (issue
  # #101): a dead forwarded agent could otherwise hang the module.
  local agent_keys _sa_rc=0
  agent_keys=$(mdoctor_timeout "$MDOCTOR_CMD_TIMEOUT_S" ssh-add -l 2>/dev/null) || _sa_rc=$?
  if [ "$_sa_rc" -eq 124 ]; then
    status_info "SSH agent: probe timed out (timeout ${MDOCTOR_CMD_TIMEOUT_S}s) — key count unknown."
    return 0
  fi
  case "$agent_keys" in
    *"no identities"*)
      status_info "SSH agent: running, no keys loaded"
      ;;
    *"Could not open"*)
      status_info "SSH agent: not running"
      ;;
    ?*)
      local loaded=0 _kline
      while IFS= read -r _kline; do
        loaded=$((loaded + 1))
      done <<< "$agent_keys"
      status_ok "SSH agent: ${loaded} key(s) loaded"
      ;;
  esac
}
