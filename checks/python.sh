#!/usr/bin/env bash
#
# checks/python.sh
# Python and pip checks
#

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
