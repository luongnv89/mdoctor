#!/usr/bin/env bash
#
# lib/benchmark.sh
# System benchmark: Disk I/O, Network, CPU
# Risk: SAFE (uses temp files, no system modification)
#

# _bench_time → high-resolution timestamp in seconds (uses Perl's Time::HiRes)
_bench_time() {
  perl -MTime::HiRes=time -e 'printf "%.6f\n", time()' 2>/dev/null || date +%s
}

# _bench_elapsed START END → prints elapsed time in seconds
_bench_elapsed() {
  awk -v s="$1" -v e="$2" 'BEGIN {printf "%.3f", e - s}'
}

run_benchmark() {
  echo "${BOLD}${BLUE}== System Benchmark ==${RESET}"
  echo
  echo "Running disk, network, and CPU benchmarks..."
  echo

  local tmp_dir="/tmp/mdoctor_bench_$$"
  mkdir -p "$tmp_dir"

  # Ensure cleanup
  trap 'rm -rf "$tmp_dir"' EXIT

  ########################################
  # DISK I/O
  ########################################
  echo "${BOLD}1. Disk I/O${RESET}"

  local disk_file="${tmp_dir}/bench_disk"
  local bs
  # macOS dd uses lowercase 'm' for megabytes; Linux uses uppercase 'M'
  if is_macos 2>/dev/null; then bs="1m"; else bs="1M"; fi
  local count=256  # 256 MB

  # Write test
  local w_start w_end w_elapsed w_speed
  w_start=$(_bench_time)
  dd if=/dev/zero of="$disk_file" bs="$bs" count="$count" 2>/dev/null
  sync
  w_end=$(_bench_time)
  w_elapsed=$(_bench_elapsed "$w_start" "$w_end")
  w_speed=$(awk -v sz=256 -v t="$w_elapsed" 'BEGIN {if(t>0) printf "%.1f", sz/t; else print "N/A"}')

  # Read test (clear disk cache first if possible)
  local r_start r_end r_elapsed r_speed
  if is_macos 2>/dev/null; then
    purge 2>/dev/null || true
  fi
  r_start=$(_bench_time)
  dd if="$disk_file" of=/dev/null bs="$bs" 2>/dev/null
  r_end=$(_bench_time)
  r_elapsed=$(_bench_elapsed "$r_start" "$r_end")
  r_speed=$(awk -v sz=256 -v t="$r_elapsed" 'BEGIN {if(t>0) printf "%.1f", sz/t; else print "N/A"}')

  rm -f "$disk_file"

  printf "  %-20s %s\n" "Write (256 MB):" "${w_speed} MB/s (${w_elapsed}s)"
  printf "  %-20s %s\n" "Read (256 MB):" "${r_speed} MB/s (${r_elapsed}s)"
  echo

  ########################################
  # NETWORK
  ########################################
  echo "${BOLD}2. Network${RESET}"

  # DNS resolution latency
  local dns_start dns_end dns_ms
  dns_start=$(_bench_time)
  nslookup google.com >/dev/null 2>&1
  dns_end=$(_bench_time)
  dns_ms=$(awk -v s="$dns_start" -v e="$dns_end" 'BEGIN {printf "%.0f", (e-s)*1000}')
  printf "  %-20s %s\n" "DNS resolution:" "${dns_ms}ms"

  # Small file download speed (100KB test)
  if command -v curl >/dev/null 2>&1; then
    local dl_start dl_end dl_elapsed
    local dl_url="http://www.google.com"
    dl_start=$(_bench_time)
    curl -sS -o /dev/null -w '' "$dl_url" 2>/dev/null || true
    dl_end=$(_bench_time)
    dl_elapsed=$(_bench_elapsed "$dl_start" "$dl_end")
    printf "  %-20s %s\n" "HTTP fetch:" "${dl_elapsed}s (google.com)"
  fi
  echo

  ########################################
  # CPU
  ########################################
  echo "${BOLD}3. CPU${RESET}"

  # Compress 10MB random data via gzip
  local cpu_file="${tmp_dir}/bench_cpu"
  dd if=/dev/urandom of="$cpu_file" bs="$bs" count=10 2>/dev/null

  local c_start c_end c_elapsed
  c_start=$(_bench_time)
  gzip -c "$cpu_file" > /dev/null
  c_end=$(_bench_time)
  c_elapsed=$(_bench_elapsed "$c_start" "$c_end")
  printf "  %-20s %s\n" "gzip 10 MB:" "${c_elapsed}s"

  rm -f "$cpu_file"

  echo
  echo "${BOLD}Results Summary${RESET}"
  echo "  ┌──────────────────────┬──────────────────┐"
  printf "  │ %-20s │ %-16s │\n" "Test" "Result"
  echo "  ├──────────────────────┼──────────────────┤"
  printf "  │ %-20s │ %13s MB/s │\n" "Disk Write (256MB)" "$w_speed"
  printf "  │ %-20s │ %13s MB/s │\n" "Disk Read (256MB)" "$r_speed"
  printf "  │ %-20s │ %15s ms │\n" "DNS Resolution" "$dns_ms"
  printf "  │ %-20s │ %16ss │\n" "CPU gzip (10MB)" "$c_elapsed"
  echo "  └──────────────────────┴──────────────────┘"
  echo

  rm -rf "$tmp_dir"
  trap - EXIT
}
