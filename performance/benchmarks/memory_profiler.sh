#!/bin/bash
# performance/benchmarks/memory_profiler.sh
# Milestone M12: Router RAM Accounting & OOM Pressure Profiler
# Interrogates /proc/meminfo and process VmRSS/VmSize to profile memory pressure.
#
# Usage:
#   ./memory_profiler.sh [--json] [--remote <host:port>]

set -euo pipefail

JSON_OUTPUT=0
REMOTE_HOST=""
REMOTE_PORT="56789"
REMOTE_USER="root"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j)
      JSON_OUTPUT=1
      shift
      ;;
    --remote|-r)
      REMOTE_HOST="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--json] [--remote <host>]"
      echo "Profiles memory allocation, slab unclaimable ratio, and top consumers."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

exec_cmd() {
  local cmd="$1"
  if [ -n "$REMOTE_HOST" ]; then
    sshpass -e ssh -p "$REMOTE_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      -o HostKeyAlgorithms=+ssh-rsa "${REMOTE_USER}@${REMOTE_HOST}" "$cmd"
  else
    eval "$cmd"
  fi
}

MEMINFO=$(exec_cmd "cat /proc/meminfo")

get_mem_val() {
  local key="$1"
  echo "$MEMINFO" | grep -E "^${key}:" | awk '{print $2}' || echo "0"
}

MEM_TOTAL=$(get_mem_val "MemTotal")
MEM_FREE=$(get_mem_val "MemFree")
MEM_AVAIL=$(get_mem_val "MemAvailable")
BUFFERS=$(get_mem_val "Buffers")
CACHED=$(get_mem_val "Cached")
SLAB=$(get_mem_val "Slab")
SRECLAIM=$(get_mem_val "SReclaimable")
SUNRECLAIM=$(get_mem_val "SUnreclaim")
SHMEM=$(get_mem_val "Shmem")

MEM_AVAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_AVAIL / $MEM_TOTAL) * 100.0}")
SLAB_PCT=$(awk "BEGIN {printf \"%.1f\", ($SLAB / $MEM_TOTAL) * 100.0}")
SUNRECLAIM_PCT=0
if [ "$SLAB" -gt 0 ]; then
  SUNRECLAIM_PCT=$(awk "BEGIN {printf \"%.1f\", ($SUNRECLAIM / $SLAB) * 100.0}")
fi

TOP_PROCS=$(exec_cmd '
for p in /proc/[0-9]*; do
  if [ -d "$p" ]; then
    pid=$(basename "$p")
    comm=$(cat "$p/comm" 2>/dev/null || echo "unknown")
    rss=$(grep -i VmRSS "$p/status" 2>/dev/null | awk "{print \$2}" || echo "0")
    size=$(grep -i VmSize "$p/status" 2>/dev/null | awk "{print \$2}" || echo "0")
    if [ -n "$rss" ] && [ "$rss" -gt 0 ]; then
      echo "$pid $comm $rss $size"
    fi
  fi
done | sort -k3 -n -r | head -n 10
')

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "{"
  echo "  \"total_kb\": $MEM_TOTAL,"
  echo "  \"free_kb\": $MEM_FREE,"
  echo "  \"available_kb\": $MEM_AVAIL,"
  echo "  \"available_pct\": $MEM_AVAIL_PCT,"
  echo "  \"buffers_kb\": $BUFFERS,"
  echo "  \"cached_kb\": $CACHED,"
  echo "  \"slab_kb\": $SLAB,"
  echo "  \"slab_pct\": $SLAB_PCT,"
  echo "  \"slab_unreclaimable_kb\": $SUNRECLAIM,"
  echo "  \"slab_unreclaimable_pct_of_slab\": $SUNRECLAIM_PCT,"
  echo "  \"top_processes\": ["
  first=1
  while read -r pid comm rss size; do
    if [ -n "$pid" ]; then
      if [ "$first" -eq 0 ]; then echo ","; fi
      first=0
      echo -n "    {\"pid\": $pid, \"comm\": \"$comm\", \"vm_rss_kb\": $rss, \"vm_size_kb\": $size}"
    fi
  done <<< "$TOP_PROCS"
  echo ""
  echo "  ]"
  echo "}"
else
  echo "=== RA82 Memory Pressure & Slab Profiling ==="
  printf "Total Usable Kernel RAM : %8d kB (%6.1f MB)\n" "$MEM_TOTAL" "$(awk "BEGIN {printf \"%.1f\", $MEM_TOTAL/1024}")"
  printf "Free Memory             : %8d kB (%6.1f MB)\n" "$MEM_FREE" "$(awk "BEGIN {printf \"%.1f\", $MEM_FREE/1024}")"
  printf "Available Memory (Real) : %8d kB (%6.1f MB) -> %s%% of Total\n" "$MEM_AVAIL" "$(awk "BEGIN {printf \"%.1f\", $MEM_AVAIL/1024}")" "$MEM_AVAIL_PCT"
  printf "Total Kernel Slab       : %8d kB (%6.1f MB) -> %s%% of Total\n" "$SLAB" "$(awk "BEGIN {printf \"%.1f\", $SLAB/1024}")" "$SLAB_PCT"
  printf "  Unreclaimable Slab    : %8d kB (%6.1f MB) -> %s%% of Slab\n" "$SUNRECLAIM" "$(awk "BEGIN {printf \"%.1f\", $SUNRECLAIM/1024}")" "$SUNRECLAIM_PCT"
  printf "  Reclaimable Slab      : %8d kB (%6.1f MB)\n" "$SRECLAIM" "$(awk "BEGIN {printf \"%.1f\", $SRECLAIM/1024}")"
  printf "Buffers / Cached / Shmem: %8d / %8d / %8d kB\n" "$BUFFERS" "$CACHED" "$SHMEM"
  echo ""
  echo "=== Top 10 Resident Memory Consumers (VmRSS) ==="
  printf "%-8s | %-20s | %-12s | %-12s\n" "PID" "Process" "VmRSS (kB)" "VmSize (kB)"
  printf -- "-------------------------------------------------------------\n"
  while read -r pid comm rss size; do
    if [ -n "$pid" ]; then
      printf "%-8s | %-20s | %-12s | %-12s\n" "$pid" "$comm" "$rss" "$size"
    fi
  done <<< "$TOP_PROCS"
  printf -- "-------------------------------------------------------------\n"
  
  if [ "$MEM_AVAIL" -lt 15000 ]; then
    echo "[ALERT] Critical memory pressure detected! MemAvailable < 15 MB."
  fi
fi
