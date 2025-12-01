#!/usr/bin/env bash
#
# checks/node.sh
# Node.js and npm checks
#

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
