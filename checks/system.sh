#!/usr/bin/env bash
#
# checks/system.sh
# System & OS information checks
#

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

  # Memory summary
  if command -v vm_stat >/dev/null 2>&1; then
    local page_size active_pages inactive_pages wired_pages
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    active_pages=$(vm_stat | awk '/Pages active/ {gsub("\\.","",$3); print $3}')
    inactive_pages=$(vm_stat | awk '/Pages inactive/ {gsub("\\.","",$3); print $3}')
    wired_pages=$(vm_stat | awk '/Pages wired down/ {gsub("\\.","",$4); print $4}')

    local total_kb used_kb free_kb
    total_kb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 ))
    used_kb=$(( (active_pages + inactive_pages + wired_pages) * page_size / 1024 ))
    free_kb=$(( total_kb - used_kb ))

    status_info "Memory total: $(kb_to_human "$total_kb"), used: $(kb_to_human "$used_kb"), free: $(kb_to_human "$free_kb")"
  fi
}
