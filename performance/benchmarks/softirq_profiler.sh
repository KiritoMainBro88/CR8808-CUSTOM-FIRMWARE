#!/bin/bash
# performance/benchmarks/softirq_profiler.sh
# Milestone M12: Dual-Core SoftIRQ & Interrupt Imbalance Benchmark Profiler
# Measures CPU0 vs CPU1 interrupt and softirq rate, distribution, and imbalance ratio.
#
# Usage:
#   ./softirq_profiler.sh [--duration <seconds>] [--json] [--remote <host:port>]

set -euo pipefail

DURATION=5
JSON_OUTPUT=0
REMOTE_HOST=""
REMOTE_PORT="56789"
REMOTE_USER="root"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --json|-j)
      JSON_OUTPUT=1
      shift
      ;;
    --remote|-r)
      REMOTE_HOST="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--duration <seconds>] [--json] [--remote <host>]"
      echo "Measures softirq and interrupt distribution between CPU0 and CPU1."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

get_softirqs() {
  if [ -n "$REMOTE_HOST" ]; then
    sshpass -e ssh -p "$REMOTE_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      -o HostKeyAlgorithms=+ssh-rsa "${REMOTE_USER}@${REMOTE_HOST}" "cat /proc/softirqs"
  else
    cat /proc/softirqs
  fi
}

get_interrupts() {
  if [ -n "$REMOTE_HOST" ]; then
    sshpass -e ssh -p "$REMOTE_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      -o HostKeyAlgorithms=+ssh-rsa "${REMOTE_USER}@${REMOTE_HOST}" "cat /proc/interrupts"
  else
    cat /proc/interrupts
  fi
}

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "=== RA82 SoftIRQ & Interrupt Profiler (Sampling ${DURATION}s window) ==="
  echo "Collecting snapshot T0..."
fi

SOFT_T0=$(get_softirqs)
INTR_T0=$(get_interrupts)

sleep "$DURATION"

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "Collecting snapshot T1..."
fi

SOFT_T1=$(get_softirqs)
INTR_T1=$(get_interrupts)

# Parse SoftIRQ Deltas
parse_soft_delta() {
  local type="$1"
  local c0_t0=$(echo "$SOFT_T0" | grep -E "^[ \t]*${type}:" | awk '{print $2}')
  local c1_t0=$(echo "$SOFT_T0" | grep -E "^[ \t]*${type}:" | awk '{print $3}')
  local c0_t1=$(echo "$SOFT_T1" | grep -E "^[ \t]*${type}:" | awk '{print $2}')
  local c1_t1=$(echo "$SOFT_T1" | grep -E "^[ \t]*${type}:" | awk '{print $3}')

  local d0=$(( c0_t1 - c0_t0 ))
  local d1=$(( c1_t1 - c1_t0 ))
  local total=$(( d0 + d1 ))
  local rate=$(awk "BEGIN {printf \"%.1f\", $total / $DURATION}")
  
  local imb=0
  if [ "$total" -gt 0 ]; then
    imb=$(awk "BEGIN {diff = ($d0 > $d1) ? ($d0 - $d1) : ($d1 - $d0); printf \"%.1f\", (diff / $total) * 100.0}")
  fi

  echo "$type $d0 $d1 $total $rate $imb"
}

TYPES=("NET_RX" "NET_TX" "TASKLET" "TIMER" "SCHED" "RCU")

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "{"
  echo "  \"duration_seconds\": $DURATION,"
  echo "  \"softirqs\": {"
  first=1
  for t in "${TYPES[@]}"; do
    res=$(parse_soft_delta "$t")
    read -r name d0 d1 tot rate imb <<< "$res"
    if [ "$first" -eq 0 ]; then echo ","; fi
    first=0
    echo -n "    \"$name\": {\"cpu0_delta\": $d0, \"cpu1_delta\": $d1, \"total\": $tot, \"rate_per_sec\": $rate, \"imbalance_pct\": $imb}"
  done
  echo ""
  echo "  }"
  echo "}"
else
  printf "%-12s | %-12s | %-12s | %-12s | %-12s | %-15s\n" "SoftIRQ Type" "CPU0 Delta" "CPU1 Delta" "Total Delta" "Rate/sec" "Imbalance %"
  printf -- "-----------------------------------------------------------------------------------------\n"
  for t in "${TYPES[@]}"; do
    res=$(parse_soft_delta "$t")
    read -r name d0 d1 tot rate imb <<< "$res"
    printf "%-12s | %-12s | %-12s | %-12s | %-12s | %-15s\n" "$name" "$d0" "$d1" "$tot" "$rate" "${imb}%"
  done
  printf -- "-----------------------------------------------------------------------------------------\n"
fi
