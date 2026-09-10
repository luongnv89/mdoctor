#!/usr/bin/env bash
#
# lib/constants.sh
# Named size, threshold and timeout values (Task 8.7). This is the single
# definition site for every bare literal the codebase compares against:
# the KB-per-GB literal occurs exactly once in all shell sources, here.
#
#
# Diagnose thresholds are overridable by documented environment variables so
# the diagnose module is tunable without editing code; everything else is a
# fixed named value. No dependencies — source this file before every other
# lib file. Several lib files also source it themselves (guarded) so unit
# tests that source one lib in isolation still see the values.
#

# Guard against double-sourcing.
if [ "${_MDOCTOR_CONSTANTS_LOADED:-false}" = true ]; then
  return 0 2>/dev/null || true
fi
_MDOCTOR_CONSTANTS_LOADED=true

########################################
# SIZE UNITS (KB-based)
########################################

export MDOCTOR_BYTES_PER_KB=1024
export MDOCTOR_KB_PER_MB=1024
export MDOCTOR_KB_PER_GB=1048576
export MDOCTOR_KB_10GB=$(( MDOCTOR_KB_PER_GB * 10 ))

########################################
# REPORT THRESHOLDS (storage-style scans)
########################################

# Below MIN_KB an entry is skipped silently; at/above WARN_KB it warns.
export MDOCTOR_REPORT_MIN_KB=102400
export MDOCTOR_REPORT_WARN_KB="$MDOCTOR_KB_PER_GB"

########################################
# TIMEOUTS (seconds; GNU timeout only)
########################################

export MDOCTOR_DU_TIMEOUT_S=30
export MDOCTOR_FIND_TIMEOUT_S=30
export MDOCTOR_DEV_FIND_TIMEOUT_S=60

########################################
# DIAGNOSE THRESHOLDS (env-overridable)
########################################
#
# Each threshold honours an MDOCTOR_DIAG_* override, e.g.
#   MDOCTOR_DIAG_CPU_HIGH=90 ./mdoctor diagnose
# warns on per-process CPU only above 90%.

# Load average: warn when load exceeds CORES * 100 by this multiple.
export MDOCTOR_DIAG_LOAD_OVER_MULT="${MDOCTOR_DIAG_LOAD_OVER_MULT:-2}"

# Per-process CPU %.
export MDOCTOR_DIAG_CPU_HIGH="${MDOCTOR_DIAG_CPU_HIGH:-80}"
export MDOCTOR_DIAG_CPU_MED="${MDOCTOR_DIAG_CPU_MED:-50}"

# Memory pressure %.
export MDOCTOR_DIAG_MEM_CRIT="${MDOCTOR_DIAG_MEM_CRIT:-95}"
export MDOCTOR_DIAG_MEM_WARN="${MDOCTOR_DIAG_MEM_WARN:-85}"

# Free-memory %.
export MDOCTOR_DIAG_MEM_FREE_CRIT="${MDOCTOR_DIAG_MEM_FREE_CRIT:-5}"
export MDOCTOR_DIAG_MEM_FREE_WARN="${MDOCTOR_DIAG_MEM_FREE_WARN:-15}"

# Swap usage %.
export MDOCTOR_DIAG_SWAP_HIGH="${MDOCTOR_DIAG_SWAP_HIGH:-80}"
export MDOCTOR_DIAG_SWAP_MED="${MDOCTOR_DIAG_SWAP_MED:-50}"

# I/O wait %.
export MDOCTOR_DIAG_IOWAIT_HIGH="${MDOCTOR_DIAG_IOWAIT_HIGH:-30}"
export MDOCTOR_DIAG_IOWAIT_MED="${MDOCTOR_DIAG_IOWAIT_MED:-15}"

# Disk usage %.
export MDOCTOR_DIAG_DISK_CRIT="${MDOCTOR_DIAG_DISK_CRIT:-95}"
export MDOCTOR_DIAG_DISK_WARN="${MDOCTOR_DIAG_DISK_WARN:-85}"

# Single-directory size (KB) worth flagging in diagnostics.
export MDOCTOR_DIAG_DIR_WARN_KB="${MDOCTOR_DIAG_DIR_WARN_KB:-$MDOCTOR_KB_PER_GB}"

# Open-file-descriptor usage %.
export MDOCTOR_DIAG_FD_HIGH="${MDOCTOR_DIAG_FD_HIGH:-80}"
export MDOCTOR_DIAG_FD_MED="${MDOCTOR_DIAG_FD_MED:-50}"

# Connection counts.
export MDOCTOR_DIAG_CONN_HIGH="${MDOCTOR_DIAG_CONN_HIGH:-5000}"
export MDOCTOR_DIAG_CONN_MED="${MDOCTOR_DIAG_CONN_MED:-1000}"

# Swap-pressure diagnosis bands (%).
export MDOCTOR_DIAG_PRESSURE_SWAP="${MDOCTOR_DIAG_PRESSURE_SWAP:-20}"
export MDOCTOR_DIAG_THRASH_SWAP="${MDOCTOR_DIAG_THRASH_SWAP:-50}"
export MDOCTOR_DIAG_THRASH_IO="${MDOCTOR_DIAG_THRASH_IO:-10}"
export MDOCTOR_DIAG_HEAVY_SWAP="${MDOCTOR_DIAG_HEAVY_SWAP:-30}"
export MDOCTOR_DIAG_HEAVY_IO="${MDOCTOR_DIAG_HEAVY_IO:-20}"

# Load/I-O correlation bands (%).
export MDOCTOR_DIAG_LOAD_IO="${MDOCTOR_DIAG_LOAD_IO:-15}"
export MDOCTOR_DIAG_IO_ALONE="${MDOCTOR_DIAG_IO_ALONE:-20}"

# System CPU share %.
export MDOCTOR_DIAG_SYS_HIGH="${MDOCTOR_DIAG_SYS_HIGH:-40}"

# sysctl hw.pagesize fallback when the probe fails.
export MDOCTOR_PAGE_SIZE_FALLBACK=4096

########################################
# BENCHMARK SIZES
########################################

# Disk benchmark payload in MiB (bs=1M, count derived below).
export MDOCTOR_BENCH_DISK_MB=256
