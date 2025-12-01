#!/usr/bin/env bash
#
# doctor.sh
# macOS health & dev-environment audit script (read-only) with health score,
# package/module update hints, and a Markdown report output.
#
# Usage:
#   ./doctor.sh
#

set -uo pipefail

########################################
# COLORS & ICONS
########################################

if command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  BOLD=""
  RESET=""
fi

CHECK="✅"
WARN="⚠️"
CROSS="❌"
INFO="ℹ️"

########################################
# PROGRESS, ACTION LIST, SCORE & REPORT
########################################

STEP_CURRENT=0
STEP_TOTAL=9  # update if you add/remove sections

ACTIONS=()
WARN_COUNT=0
FAIL_COUNT=0

LOG_PATHS=()
LOG_DESCS=()

REPORT_MD=""

########################################
# Markdown helpers
########################################

md_append() {
  local line="${1-}"
  [ -z "${REPORT_MD:-}" ] && return
  printf '%s\n' "$line" >> "$REPORT_MD"
}

md_init() {
  REPORT_MD="/tmp/macos_doctor_$(date +%Y%m%d_%H%M%S).md"
  : > "$REPORT_MD"  # truncate/create
  md_append "# macOS Doctor Report"
  md_append ""
  md_append "- Generated on: **$(date)**"
  md_append "- Hostname: **$(hostname)**"
  md_append ""
}

########################################
# UI helpers
########################################

step() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  local title="$1"
  echo
  echo "${BOLD}➤ [${STEP_CURRENT}/${STEP_TOTAL}] ${title}${RESET}"
  echo "----------------------------------------"

  md_append ""
  md_append "## [${STEP_CURRENT}/${STEP_TOTAL}] ${title}"
  md_append ""
}

section_title() {
  local title="$1"
  echo
  echo "${BOLD}${BLUE}== ${title} ==${RESET}"

  md_append ""
  md_append "## ${title}"
  md_append ""
}

status_ok() {
  local msg="$1"
  echo "  ${CHECK} ${GREEN}${msg}${RESET}"
  md_append "- ✅ ${msg}"
}

status_warn() {
  local msg="$1"
  WARN_COUNT=$((WARN_COUNT + 1))
  echo "  ${WARN} ${YELLOW}${msg}${RESET}"
  md_append "- ⚠️ ${msg}"
}

status_fail() {
  local msg="$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "  ${CROSS} ${RED}${msg}${RESET}"
  md_append "- ❌ ${msg}"
}

status_info() {
  local msg="$1"
  echo "  ${INFO} ${msg}"
  md_append "- ℹ️ ${msg}"
}

add_action() {
  local msg="${1-}"
  [ -n "${msg}" ] && ACTIONS+=("$msg")
}

add_log_file() {
  local path="${1-}"
  local desc="${2-}"
  if [ -n "${path}" ]; then
    LOG_PATHS+=("$path")
    LOG_DESCS+=("$desc")
  fi
}

########################################
# HELPERS
########################################

kb_to_human() {
  local kb="${1:-0}"
  if (( kb >= 1048576 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f GB", kb/1048576}'
  elif (( kb >= 1024 )); then
    awk -v kb="$kb" 'BEGIN {printf "%.2f MB", kb/1024}'
  else
    printf "%d KB" "$kb"
  fi
}

disk_used_pct_root() {
  df -H / | awk 'NR==2 {gsub("%","",$5); print $5}'
}

########################################
# CHECKS
########################################

check_system() {
  step "System & OS"

  local product_name product_version build uname_arch uptime_str

  product_name=$(sw_vers -productName 2>/dev/null || echo "Unknown")
  product_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  build=$(sw_vers -buildVersion 2>/dev/null || echo "Unknown")
  uname_arch=$(uname -m 2>/dev/null || echo "Unknown")
  uptime_str=$(uptime | sed 's/.*up *//; s/, *[0-9]* user.*//')

  status_info "macOS: ${product_name} ${product_version} (build ${build})"
  status_info "Architecture: ${uname_arch}"
  status_info "Uptime: ${uptime_str}"

  # Load average
  local load
  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2","$3","$4}')
  status_info "Load average (1/5/15 min): ${load}"

  # Memory summary (from vm_stat)
  if command -v vm_stat >/dev/null 2>&1; then
    local page_size free_pages active_pages inactive_pages speculative_pages wired_pages
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    free_pages=$(vm_stat | awk '/Pages free/ {gsub("\\.","",$3); print $3}')
    active_pages=$(vm_stat | awk '/Pages active/ {gsub("\\.","",$3); print $3}')
    inactive_pages=$(vm_stat | awk '/Pages inactive/ {gsub("\\.","",$3); print $3}')
    speculative_pages=$(vm_stat | awk '/Pages speculative/ {gsub("\\.","",$3); print $3}')
    wired_pages=$(vm_stat | awk '/Pages wired down/ {gsub("\\.","",$4); print $4}')

    local free_kb used_kb total_kb
    free_kb=$(( (free_pages + speculative_pages) * page_size / 1024 ))
    used_kb=$(( (active_pages + inactive_pages + wired_pages) * page_size / 1024 ))
    total_kb=$(( free_kb + used_kb ))

    status_info "Memory total: $(kb_to_human "$total_kb"), used: $(kb_to_human "$used_kb"), free: $(kb_to_human "$free_kb")"
  fi
}

check_disk() {
  step "Disk health & free space"

  local used_pct
  used_pct=$(disk_used_pct_root)

  status_info "Root filesystem usage: ${used_pct}%"
  df -h / | awk 'NR==1 || NR==2 {print "  "$0}'

  if (( used_pct >= 90 )); then
    status_fail "Disk is almost full (>= 90%)."
    add_action "Free disk space on / (currently ${used_pct}% used): delete large files, clean caches, or move archives to external storage."
  elif (( used_pct >= 80 )); then
    status_warn "Disk is getting full (>= 80%)."
    add_action "Plan to free space on / soon (currently ${used_pct}% used)."
  else
    status_ok "Disk usage is within a healthy range."
  fi
}

check_updates_basic() {
  step "Basic update status (Spotlight & softwareupdate)"

  # Spotlight indexing
  if command -v mdutil >/dev/null 2>&1; then
    local md
    md=$(mdutil -s / 2>/dev/null || true)
    status_info "Spotlight: ${md}"
  fi

  # softwareupdate quick check
  if command -v softwareupdate >/dev/null 2>&1; then
    if softwareupdate -l 2>/dev/null | grep -qi "No new software available"; then
      status_ok "No macOS software updates reported."
    else
      status_warn "There may be macOS updates available."
      add_action "Run 'softwareupdate -l' and apply pending macOS updates via System Settings."
    fi
  else
    status_warn "softwareupdate command not available."
    add_action "Ensure macOS softwareupdate tools are available (usually present by default; if missing, investigate OS installation)."
  fi
}

check_homebrew() {
  step "Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    status_warn "Homebrew is not installed."
    add_action "Install Homebrew (if you need a package manager): /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    return
  fi

  local brew_ver
  brew_ver=$(brew --version 2>/dev/null | head -n1)
  status_ok "Found Homebrew: ${brew_ver}"

  # brew doctor
  local brew_doctor_log="/tmp/brew_doctor.log"
  if brew doctor >"$brew_doctor_log" 2>&1; then
    status_ok "brew doctor reports no major issues."
  else
    status_warn "brew doctor found issues – see ${brew_doctor_log}."
    add_action "Open ${brew_doctor_log} and follow 'brew doctor' suggestions to fix Homebrew issues."
  fi
  add_log_file "$brew_doctor_log" "Homebrew doctor output"

  # outdated formulae – log full list and show short summary
  local outdated_file="/tmp/brew_outdated.log"
  brew outdated >"$outdated_file" 2>/dev/null || true
  local outdated_count
  outdated_count=$(wc -l <"$outdated_file" 2>/dev/null | tr -d ' ' || echo 0)

  if [[ "$outdated_count" == "0" ]]; then
    status_ok "No outdated Homebrew formulae."
  else
    status_warn "${outdated_count} outdated Homebrew formula(e) found."
    status_info "Sample outdated formulae:"
    head -n 5 "$outdated_file" | sed 's/^/    - /'
    [ "$outdated_count" -gt 5 ] && status_info "    … see full list in ${outdated_file}"

    add_action "Update Homebrew packages: 
       1) 'brew update' 
       2) 'brew upgrade' 
       3) Optionally 'brew cleanup -s' to remove old versions.
       Full outdated list: ${outdated_file}"

    add_log_file "$outdated_file" "Outdated Homebrew formulae"
  fi
}

check_node_npm() {
  step "Node.js & npm"

  local has_node=false

  if command -v node >/dev/null 2>&1; then
    status_ok "Node.js: $(node -v)"
    has_node=true
  else
    status_warn "Node.js not found (node)."
    add_action "Install Node.js if needed (e.g., 'brew install node' or from nodejs.org)."
  fi

  if command -v npm >/dev/null 2>&1; then
    status_ok "npm: $(npm -v)"

    # npm doctor
    local npm_doctor_log="/tmp/npm_doctor.log"
    if npm doctor >"$npm_doctor_log" 2>&1; then
      status_ok "npm doctor passed."
    else
      status_warn "npm doctor reported issues – see ${npm_doctor_log}."
      add_action "Review npm issues in ${npm_doctor_log} and fix reported problems (permissions, PATH, etc.)."
    fi
    add_log_file "$npm_doctor_log" "npm doctor output"

    # outdated global packages – save full list
    local npm_out_file="/tmp/npm_outdated_global.log"
    npm outdated -g --depth=0 >"$npm_out_file" 2>/dev/null || true

    # Count excluding header line (if present)
    local count
    if grep -qE 'Package|Current|Wanted|Latest' "$npm_out_file" 2>/dev/null; then
      count=$(tail -n +2 "$npm_out_file" 2>/dev/null | wc -l | tr -d ' ')
    else
      count=$(wc -l <"$npm_out_file" 2>/dev/null | tr -d ' ')
    fi

    if [[ -z "$count" ]] || [[ "$count" == "0" ]]; then
      status_ok "No outdated global npm packages (or none installed)."
    else
      status_warn "${count} outdated global npm package(s)."
      status_info "Sample outdated global npm packages:"
      head -n 5 "$npm_out_file" | sed 's/^/    - /'
      [ "$count" -gt 5 ] && status_info "    … see full list in ${npm_out_file}"

      add_action "Update global npm packages:
       - List outdated: 'npm outdated -g --depth=0'
       - Update all:   'npm update -g'
       - Or update specific packages: 'npm update -g <package>'
       Full outdated list: ${npm_out_file}
       For project-specific deps, run 'npm outdated' in each project directory."

      add_log_file "$npm_out_file" "Outdated global npm packages"
    fi
  else
    status_warn "npm not found."
    if [ "$has_node" = true ]; then
      add_action "npm missing but Node is installed – reinstall Node.js or ensure npm is on PATH."
    fi
  fi
}

check_python() {
  step "Python & pip"

  local has_py3=false

  if command -v python3 >/dev/null 2>&1; then
    status_ok "Python3: $(python3 --version 2>/dev/null)"
    has_py3=true
  else
    status_warn "python3 not found."
    add_action "Install Python 3 if needed (e.g., 'brew install python' or from python.org)."
  fi

  if command -v pip3 >/dev/null 2>&1; then
    status_ok "pip3: $(pip3 --version 2>/dev/null)"

    # pip3 check (dependency issues)
    local pip_check_log="/tmp/pip3_check.log"
    if pip3 check >"$pip_check_log" 2>&1; then
      status_ok "pip3 check passed (no dependency issues detected in current environment)."
    else
      status_warn "pip3 check reported issues – see ${pip_check_log}."
      add_action "Review pip dependency issues in ${pip_check_log} and resolve version conflicts."
    fi
    add_log_file "$pip_check_log" "pip3 dependency check output"

    # pip3 outdated – full list to file
    local pip_out_file="/tmp/pip3_outdated.log"
    pip3 list --outdated >"$pip_out_file" 2>/dev/null || true
    local pip_count
    if grep -qE 'Package|Version|Latest' "$pip_out_file" 2>/dev/null; then
      pip_count=$(tail -n +3 "$pip_out_file" 2>/dev/null | wc -l | tr -d ' ')
    else
      pip_count=$(wc -l <"$pip_out_file" 2>/dev/null | tr -d ' ')
    fi

    if [[ -z "$pip_count" ]] || [[ "$pip_count" == "0" ]]; then
      status_ok "No outdated pip3 packages in the current environment."
    else
      status_warn "${pip_count} outdated pip3 package(s) in the current environment."
      status_info "Sample outdated Python packages:"
      head -n 8 "$pip_out_file" | sed 's/^/    - /'
      [ "$pip_count" -gt 8 ] && status_info "    … see full list in ${pip_out_file}"

      add_action "Update Python packages in this environment:
       - List outdated: 'pip3 list --outdated'
       - Update one:    'pip3 install --upgrade <package>'
       - Update many (be careful in system envs): 'pip3 list --outdated | awk \"NR>2 {print \\\$1}\" | xargs -n1 pip3 install -U'
       Full outdated list: ${pip_out_file}
       Tip: Prefer virtualenvs/poetry for per-project management."

      add_log_file "$pip_out_file" "Outdated Python packages (pip3, current env)"
    fi
  else
    status_warn "pip3 not found."
    if [ "$has_py3" = true ]; then
      add_action "Install pip3 for Python 3 (e.g., 'python3 -m ensurepip --upgrade')."
    fi
  fi
}

check_dev_tools() {
  step "Xcode Command Line Tools, Git & Docker"

  # Xcode Command Line Tools
  if xcode-select -p >/dev/null 2>&1; then
    status_ok "Xcode Command Line Tools installed: $(xcode-select -p)"
  else
    status_warn "Xcode Command Line Tools not found."
    add_action "Install Xcode Command Line Tools: run 'xcode-select --install'."
  fi

  # Git
  if command -v git >/dev/null 2>&1; then
    status_ok "Git: $(git --version)"
  else
    status_warn "Git not found."
    add_action "Install Git via Xcode CLT ('xcode-select --install') or 'brew install git'."
  fi

  # Docker
  if command -v docker >/dev/null 2>&1; then
    local docker_info_log="/tmp/docker_info.log"
    if docker info >"$docker_info_log" 2>&1; then
      status_ok "Docker is installed and daemon is reachable."
    else
      status_warn "Docker CLI found but daemon not reachable."
      add_action "Start Docker Desktop or ensure the Docker daemon is running, then re-run 'docker info'."
    fi
    add_log_file "$docker_info_log" "Docker info output"
  else
    status_info "Docker not installed (skipping)."
  fi
}

########################################
# SHELL CONFIG CHECKS
########################################

check_one_shell_file() {
  local name="${1-}"
  local shell_type="${2-}"
  local file="${HOME}/${name}"

  if [ -z "${name}" ]; then
    return
  fi

  if [ ! -f "$file" ]; then
    status_info "No ${name} found (this is fine if you don't customize ${shell_type})."
    return
  fi

  status_ok "Found ${name}"

  # Syntax check
  if [ "$shell_type" = "zsh" ] && command -v zsh >/dev/null 2>&1; then
    if zsh -n "$file" >/dev/null 2>&1; then
      status_ok "Syntax OK for ${name} (zsh -n)."
    else
      status_warn "Possible syntax errors in ${name} (zsh -n failed)."
      add_action "Open ${file} and fix syntax errors reported by 'zsh -n ${file}'."
    fi
  elif [ "$shell_type" = "bash" ] && command -v bash >/dev/null 2>&1; then
    if bash -n "$file" >/dev/null 2>&1; then
      status_ok "Syntax OK for ${name} (bash -n)."
    else
      status_warn "Possible syntax errors in ${name} (bash -n failed)."
      add_action "Open ${file} and fix syntax errors reported by 'bash -n ${file}'."
    fi
  fi

  # Look for 'source' or '.' commands that reference missing files
  while IFS= read -r line; do
    case "$line" in
      \#*|"") continue ;;
    esac

    if echo "$line" | grep -qE '^\s*(source|\.)\s+'; then
      local target expanded

      target=$(echo "$line" | sed -E 's/^\s*(source|\.)\s+//; s/[;&|].*//')
      target=$(echo "$target" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
      target=$(echo "$target" | sed -E 's/^["'\'']//; s/["'\'']$//')

      case "$target" in
        /*)
          expanded="$target"
          ;;
        ~/*)
          expanded="${HOME}${target#\~}"
          ;;
        *)
          expanded="${HOME}/${target}"
          ;;
      esac

      if [ -n "$expanded" ] && [ ! -e "$expanded" ]; then
        status_warn "In ${name}: sources missing file '${target}'."
        add_action "Edit ${file} to fix or remove 'source ${target}' (file does not exist at ${expanded})."
      fi
    fi
  done < "$file"
}

check_shell_configs() {
  step "Shell configuration files (.zshrc, .bashrc, etc.)"

  check_one_shell_file ".zshrc" "zsh"
  check_one_shell_file ".bashrc" "bash"
  check_one_shell_file ".bash_profile" "bash"
  check_one_shell_file ".profile" "sh"
}

########################################
# NETWORK
########################################

check_network() {
  step "Network connectivity (basic)"

  if ping -c 1 -W 1000 1.1.1.1 >/dev/null 2>&1; then
    status_ok "Can reach the internet (ping 1.1.1.1 succeeded)."
  else
    status_warn "Ping to 1.1.1.1 failed."
    add_action "Check network connectivity or firewall rules (ping to 1.1.1.1 fails)."
  fi

  if ping -c 1 -W 1000 github.com >/dev/null 2>&1; then
    status_ok "Can reach github.com."
  else
    status_warn "Cannot reach github.com."
    add_action "Check DNS / network configuration: unable to reach github.com."
  fi
}

########################################
# MAIN
########################################

main() {
  md_init

  section_title "macOS Doctor – System & Dev Environment Audit"
  echo "${INFO} This script is read-only: it does NOT change anything, only reports status."
  md_append "- ℹ️ This script is read-only: it does **not** modify your system."
  echo

  check_system
  check_disk
  check_updates_basic
  check_homebrew
  check_node_npm
  check_python
  check_dev_tools
  check_shell_configs
  check_network

  echo
  section_title "Summary"

  local MAX_SCORE=100
  local penalty
  local score
  penalty=$(( WARN_COUNT * 4 + FAIL_COUNT * 8 ))
  score=$(( MAX_SCORE - penalty ))
  if (( score < 0 )); then
    score=0
  fi

  local rating
  if (( score >= 90 )); then
    rating="Excellent"
  elif (( score >= 75 )); then
    rating="Good"
  elif (( score >= 50 )); then
    rating="Needs attention"
  else
    rating="Critical – fix issues ASAP"
  fi

  echo "Health score: ${BOLD}${score}/100${RESET} (${rating})"
  echo "Warnings: ${WARN_COUNT}, Failures: ${FAIL_COUNT}"
  echo

  md_append ""
  md_append "## Summary"
  md_append ""
  md_append "- Health score: **${score}/100** (${rating})"
  md_append "- Warnings: **${WARN_COUNT}**, Failures: **${FAIL_COUNT}**"
  md_append ""

  if ((${#ACTIONS[@]} > 0)); then
    echo "${BOLD}Actionable next steps:${RESET}"
    md_append "### Actionable next steps"
    md_append ""
    local i=1
    for action in "${ACTIONS[@]}"; do
      echo "  ${i}. ${action}"
      md_append "${i}. ${action}"
      i=$((i + 1))
    done
  else
    local msg="No immediate actions detected. Your system/dev setup looks healthy."
    echo "  ${CHECK} ${GREEN}${msg}${RESET}"
    md_append "### Actionable next steps"
    md_append ""
    md_append "- ✅ ${msg}"
  fi

  if ((${#LOG_PATHS[@]} > 0)); then
    echo
    echo "${BOLD}Detailed logs generated in this run:${RESET}"
    md_append ""
    md_append "### Detailed logs"
    md_append ""
    local j=0
    local n=${#LOG_PATHS[@]}
    while (( j < n )); do
      local p="${LOG_PATHS[$j]}"
      local d="${LOG_DESCS[$j]}"
      if [ -f "$p" ]; then
        printf "  %-32s # %s\n" "$p" "$d"
        md_append "- \`$p\` — ${d}"
      fi
      j=$((j + 1))
    done
  fi

  echo
  echo "${BOLD}Markdown report saved to:${RESET} ${REPORT_MD}"
  echo
  echo "${BOLD}Done.${RESET}"
  md_append ""
  md_append "_End of report._"
}

main "$@"
