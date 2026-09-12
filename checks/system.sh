#!/usr/bin/env bash
#
# checks/system.sh
# System & OS information checks
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
check_system() {
  step "System & OS"

  local uname_arch uptime_str
  uname_arch=$(uname -m 2>/dev/null || echo "Unknown")
  uptime_str=$(uptime | sed 's/.*up *//; s/, *[0-9]* user.*//')

  if is_macos; then
    local product_name product_version build
    product_name=$(sw_vers -productName 2>/dev/null || echo "Unknown")
    product_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
    build=$(sw_vers -buildVersion 2>/dev/null || echo "Unknown")
    status_info "macOS: ${product_name} ${product_version} (build ${build})"
  else
    status_info "OS: ${MDOCTOR_OS_NAME:-$(uname -s)}"
  fi

  status_info "Architecture: ${uname_arch}"
  status_info "Uptime: ${uptime_str}"

  # Load average (stays inline by design, #88 note: this reports the
  # 1/5/15-min triple for display, while perf_probe_load serves the
  # 1-min + core-count threshold pair — different shapes, not a pure
  # duplicate, so it is out of scope for the shared probes).
  local load _l1="" _l5="" _l15="" _lrest _la
  if is_macos; then
    # "{ 1.23 4.56 7.89 }" → fields 2/3/4 joined by commas — the retired
    # sysctl|awk '{print $2","$3","$4}' (issue #98). Empty sysctl output
    # leaves load empty, exactly like awk on no input.
    _la=$(sysctl -n vm.loadavg 2>/dev/null || true)
    read -r _lrest _l1 _l5 _l15 _ <<< "$_la"
    if [ -n "$_la" ]; then
      load="${_l1},${_l5},${_l15}"
    else
      load=""
    fi
  else
    if [ -r /proc/loadavg ]; then
      read -r _l1 _l5 _l15 _lrest < /proc/loadavg
    fi
    if [ -n "$_l1" ]; then
      load="${_l1},${_l5},${_l15}"
    else
      load=""
    fi
  fi
  if [ -n "$load" ]; then
    status_info "Load average (1/5/15 min): ${load}"
  fi

  # Memory summary — one vm_stat snapshot parsed in-shell (issue #98:
  # was three vm_stat invocations for three fields of one report).
  if is_macos; then
    if command -v vm_stat >/dev/null 2>&1; then
      local page_size active_pages="" inactive_pages="" wired_pages=""
      local _vm_out _vml _vv
      page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
      _vm_out=$(vm_stat 2>/dev/null || true)
      while IFS= read -r _vml; do
        case "$_vml" in
          *"Pages active:"*)
            read -r _ _ _vv _ <<< "$_vml"
            active_pages="${_vv//./}"
            ;;
          *"Pages inactive:"*)
            read -r _ _ _vv _ <<< "$_vml"
            inactive_pages="${_vv//./}"
            ;;
          *"Pages wired down:"*)
            read -r _ _ _ _vv _ <<< "$_vml"
            wired_pages="${_vv//./}"
            ;;
        esac
      done <<< "$_vm_out"

      local total_kb used_kb free_kb
      local total_bytes
      total_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
      total_kb=$(( ${total_bytes:-0} / 1024 ))
      used_kb=$(( (active_pages + inactive_pages + wired_pages) * page_size / 1024 ))
      free_kb=$(( total_kb - used_kb ))

      status_info "Memory total: $(kb_to_human "$total_kb"), used: $(kb_to_human "$used_kb"), free: $(kb_to_human "$free_kb")"
    fi
  else
    # Linux: parse /proc/meminfo — one in-shell pass for both fields
    # (issue #98; was two awk opens of the same file).
    if [ -r /proc/meminfo ]; then
      local mem_total_kb="" mem_avail_kb="" mem_used_kb
      local _mk _mv _mline
      while IFS= read -r _mline; do
        read -r _mk _mv _ <<< "$_mline"
        case "$_mk" in
          MemTotal:)     mem_total_kb="$_mv" ;;
          MemAvailable:) mem_avail_kb="$_mv" ;;
        esac
      done < /proc/meminfo
      mem_used_kb=$(( ${mem_total_kb:-0} - ${mem_avail_kb:-0} ))
      local mem_free_kb=$((mem_avail_kb))
      status_info "Memory total: $(kb_to_human "$mem_total_kb"), used: $(kb_to_human "$mem_used_kb"), free: $(kb_to_human "$mem_free_kb")"
    fi
  fi
}
