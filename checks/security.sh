#!/usr/bin/env bash
#
# checks/security.sh
# Security & privacy audit (read-only, SAFE)
# Category: System
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
check_security() {
  step "Security & Privacy"

  if is_macos; then
    # Firewall status
    local fw_status
    fw_status=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
    # Case-insensitive substring tests via case globs — zero forks
    # (issue #98: was echo|grep -qi per test).
    case "$fw_status" in
      *[Ee][Nn][Aa][Bb][Ll][Ee][Dd]*)
        status_ok "Firewall: enabled"
        ;;
      *[Dd][Ii][Ss][Aa][Bb][Ll][Ee][Dd]*)
        status_warn "Firewall: disabled"
        add_action "Enable the macOS firewall: System Settings > Network > Firewall"
        ;;
      *)
        status_info "Firewall status: could not determine"
        ;;
    esac

    # FileVault / disk encryption
    local fv_status
    fv_status=$(fdesetup status 2>/dev/null || true)
    case "$fv_status" in
      *[Oo][Nn]*)
        status_ok "FileVault: enabled"
        ;;
      *[Oo][Ff][Ff]*)
        status_warn "FileVault: disabled (disk not encrypted)"
        add_action "Enable FileVault for disk encryption: System Settings > Privacy & Security > FileVault"
        ;;
      *)
        status_info "FileVault status: could not determine"
        ;;
    esac

    # System Integrity Protection
    local sip_status
    sip_status=$(csrutil status 2>/dev/null || true)
    case "$sip_status" in
      *[Ee][Nn][Aa][Bb][Ll][Ee][Dd]*)
        status_ok "System Integrity Protection (SIP): enabled"
        ;;
      *[Dd][Ii][Ss][Aa][Bb][Ll][Ee][Dd]*)
        status_fail "System Integrity Protection (SIP): disabled"
        add_action "SIP is disabled. This is a security risk. Re-enable via Recovery Mode: csrutil enable"
        ;;
      *)
        status_info "SIP status: could not determine"
        ;;
    esac

    # Gatekeeper
    local gk_status
    gk_status=$(spctl --status 2>/dev/null || true)
    case "$gk_status" in
      *[Ee][Nn][Aa][Bb][Ll][Ee][Dd]*)
        status_ok "Gatekeeper: enabled"
        ;;
      *[Dd][Ii][Ss][Aa][Bb][Ll][Ee][Dd]*)
        status_warn "Gatekeeper: disabled"
        add_action "Enable Gatekeeper: sudo spctl --master-enable"
        ;;
      *)
        status_info "Gatekeeper status: could not determine"
        ;;
    esac

    # Remote Login (SSH)
    local remote_login
    remote_login=$(systemsetup -getremotelogin 2>/dev/null || true)
    case "$remote_login" in
      *[Oo][Nn]*)
        status_info "Remote Login (SSH): enabled"
        ;;
      *[Oo][Ff][Ff]*)
        status_ok "Remote Login (SSH): disabled"
        ;;
    esac

    # Screen Sharing + Remote Management — one launchctl snapshot counts
    # both labels (issue #98: was a second launchctl|grep -c per label).
    local screen_sharing=0 remote_mgmt=0
    local _ll_out _lline
    _ll_out=$(launchctl list 2>/dev/null || true)
    while IFS= read -r _lline; do
      case "$_lline" in
        *com.apple.screensharing*)  screen_sharing=$((screen_sharing + 1)) ;;
        *com.apple.RemoteDesktop*)  remote_mgmt=$((remote_mgmt + 1)) ;;
      esac
    done <<< "$_ll_out"
    if (( screen_sharing > 0 )); then
      status_info "Screen Sharing: active"
    fi
    if (( remote_mgmt > 0 )); then
      status_info "Remote Management: active"
    fi

    # Automatic login
    local auto_login
    auto_login=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || echo "")
    if [ -n "$auto_login" ]; then
      status_warn "Automatic login enabled for user: ${auto_login}"
      add_action "Disable automatic login: System Settings > Users & Groups > Automatic login"
    fi
  else
    # Linux: firewall, disk encryption, SSH, unattended upgrades

    # Firewall (ufw or iptables)
    # Read-only check: never prompt for a password. Privileged probes run
    # only when sudo is available without a password (`sudo -n true`
    # fails instead of prompting); otherwise report "requires sudo to verify".
    if command -v ufw >/dev/null 2>&1; then
      local ufw_status
      ufw_status=$(ufw status 2>/dev/null || echo "")
      if [ -z "$ufw_status" ] && sudo -n true 2>/dev/null; then
        ufw_status=$(sudo -n ufw status 2>/dev/null || echo "")
      fi
      # NOTE: "inactive" must be tested before "active" — the latter
      # is a substring of the former ("Status: inactive").
      case "$ufw_status" in
        *[Ii][Nn][Aa][Cc][Tt][Ii][Vv][Ee]*)
          status_warn "Firewall (ufw): inactive"
          add_action "Enable the firewall: sudo ufw enable"
          ;;
        *[Aa][Cc][Tt][Ii][Vv][Ee]*)
          status_ok "Firewall (ufw): active"
          ;;
        "")
          status_info "Firewall (ufw): requires sudo to verify"
          ;;
        *)
          status_info "Firewall (ufw): could not determine status"
          ;;
      esac
    elif command -v iptables >/dev/null 2>&1; then
      local ipt_rules="" ipt_rules_raw
      if sudo -n true 2>/dev/null; then
        # Count rule lines in-shell — the retired grep -cv skipped
        # blank lines and Chain/target headers (issue #98).
        local _ipt_out _iptl _ipt_n=0
        _ipt_out=$(sudo -n iptables -L -n 2>/dev/null || true)
        while IFS= read -r _iptl; do
          case "$_iptl" in
            ""|Chain*|target*) ;;
            *) _ipt_n=$((_ipt_n + 1)) ;;
          esac
        done <<< "$_ipt_out"
        ipt_rules_raw="$_ipt_n"
        ipt_rules=$(to_int "$ipt_rules_raw")
      fi
      if [ -z "$ipt_rules" ]; then
        status_info "Firewall (iptables): requires sudo to verify"
      elif (( ipt_rules > 0 )); then
        status_ok "Firewall (iptables): ${ipt_rules} rules active"
      else
        status_warn "Firewall (iptables): no rules configured"
        add_action "Consider configuring firewall rules with iptables or installing ufw."
      fi
    else
      status_info "No firewall tool found (ufw/iptables)"
    fi

    # Disk encryption (LUKS)
    if command -v lsblk >/dev/null 2>&1; then
      local crypt_count crypt_count_raw
      local _lb_out _lbl _crypt_n=0
      _lb_out=$(lsblk -o TYPE 2>/dev/null || true)
      while IFS= read -r _lbl; do
        case "$_lbl" in
          *crypt*) _crypt_n=$((_crypt_n + 1)) ;;
        esac
      done <<< "$_lb_out"
      crypt_count_raw="$_crypt_n"
      crypt_count=$(to_int "$crypt_count_raw")
      if (( crypt_count > 0 )); then
        status_ok "Disk encryption (LUKS): ${crypt_count} encrypted volume(s)"
      else
        status_info "Disk encryption: no LUKS volumes detected"
      fi
    fi

    # SSH server
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
        status_info "SSH server: running"
      else
        status_ok "SSH server: not running"
      fi
    fi

    # Unattended upgrades (Debian-family only) — the '^ii' line test
    # runs in-shell (issue #98).
    if is_debian; then
      local _dpkg_out
      _dpkg_out=$(dpkg -l unattended-upgrades 2>/dev/null || true)
      case "$_dpkg_out" in
        ii*|*$'\n'ii*)
          status_ok "Unattended upgrades: installed"
          ;;
        *)
          status_warn "Unattended upgrades: not installed"
          add_action "Consider installing unattended-upgrades for automatic security updates."
          ;;
      esac
    else
      status_info "Unattended upgrades: N/A on this distro."
    fi
  fi

  # Cross-platform: processes listening on TCP ports — in-shell line
  # count over one snapshot (issue #98: was tail|wc -l|tr per probe).
  # The first line is the header (the retired tail -n +2).
  local listening_count=""
  local _have_probe=0
  local _listen_out="" _lstn_line _lstn_seen=0
  if is_macos; then
    _listen_out=$(lsof -iTCP -sTCP:LISTEN -P 2>/dev/null || true)
    _have_probe=1
  elif ! command -v ss >/dev/null 2>&1; then
    # Task 2.5: guarded ss; absent ss reports a skip, never an error.
    status_info "Skipping listening-ports probe: ss not found."
  else
    _listen_out=$(ss -tlnp 2>/dev/null || true)
    _have_probe=1
  fi
  if (( _have_probe )); then
    listening_count=0
    while IFS= read -r _lstn_line; do
      _lstn_seen=$((_lstn_seen + 1))
      if (( _lstn_seen > 1 )); then
        listening_count=$((listening_count + 1))
      fi
    done <<< "$_listen_out"
  fi
  if [ -n "$listening_count" ] && (( listening_count > 0 )); then
    status_info "Processes listening on TCP ports: ${listening_count}"
  fi
}
