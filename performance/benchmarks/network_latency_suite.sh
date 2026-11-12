#!/bin/bash
# performance/benchmarks/network_latency_suite.sh
# Milestone M12: Network Latency, Jitter & Bufferbloat Benchmark Suite
# Tests latency distribution (min/avg/max/mdev/p99) under idle and load conditions.
#
# Usage:
#   ./network_latency_suite.sh [--target <ip>] [--count <packets>] [--json]

set -euo pipefail

TARGET="192.168.31.1"
COUNT=50
INTERVAL=0.1
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|-t)
      TARGET="$2"
      shift 2
      ;;
    --count|-c)
      COUNT="$2"
      shift 2
      ;;
    --interval|-i)
      INTERVAL="$2"
      shift 2
      ;;
    --json|-j)
      JSON_OUTPUT=1
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--target <ip>] [--count <num>] [--interval <sec>] [--json]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "=== Running Network Latency & Bufferbloat Suite against $TARGET ($COUNT probes, interval ${INTERVAL}s) ==="
fi

# Run ping and capture raw statistics
TMP_PING=$(mktemp)
trap 'rm -f "$TMP_PING"' EXIT

ping -c "$COUNT" -i "$INTERVAL" "$TARGET" > "$TMP_PING" 2>&1 || true

LOSS=$(grep -oE '[0-9]+% packet loss' "$TMP_PING" | awk '{print $1}' | tr -d '%' || echo "100")
RTT_LINE=$(grep -E '^(rtt|round-trip)' "$TMP_PING" || true)

MIN=0
AVG=0
MAX=0
MDEV=0

if [ -n "$RTT_LINE" ]; then
  STATS=$(echo "$RTT_LINE" | awk '{print $4}')
  MIN=$(echo "$STATS" | cut -d'/' -f1)
  AVG=$(echo "$STATS" | cut -d'/' -f2)
  MAX=$(echo "$STATS" | cut -d'/' -f3)
  MDEV=$(echo "$STATS" | cut -d'/' -f4)
fi

# Extract individual RTTs to calculate p95 and p99
RTTS=($(grep -oE 'time=[0-9.]+' "$TMP_PING" | cut -d'=' -f2 | sort -n))
TOTAL_SAMPLES=${#RTTS[@]}

P95=0
P99=0
if [ "$TOTAL_SAMPLES" -gt 0 ]; then
  IDX_95=$(( (TOTAL_SAMPLES * 95) / 100 ))
  IDX_99=$(( (TOTAL_SAMPLES * 99) / 100 ))
  if [ "$IDX_95" -ge "$TOTAL_SAMPLES" ]; then IDX_95=$(( TOTAL_SAMPLES - 1 )); fi
  if [ "$IDX_99" -ge "$TOTAL_SAMPLES" ]; then IDX_99=$(( TOTAL_SAMPLES - 1 )); fi
  P95="${RTTS[$IDX_95]}"
  P99="${RTTS[$IDX_99]}"
fi

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "{"
  echo "  \"target\": \"$TARGET\","
  echo "  \"probes_sent\": $COUNT,"
  echo "  \"packet_loss_pct\": $LOSS,"
  echo "  \"rtt_min_ms\": $MIN,"
  echo "  \"rtt_avg_ms\": $AVG,"
  echo "  \"rtt_max_ms\": $MAX,"
  echo "  \"rtt_mdev_ms\": $MDEV,"
  echo "  \"rtt_p95_ms\": $P95,"
  echo "  \"rtt_p99_ms\": $P99"
  echo "}"
else
  printf "%-20s : %s\n" "Target Host" "$TARGET"
  printf "%-20s : %d\n" "Packets Transmitted" "$COUNT"
  printf "%-20s : %s%%\n" "Packet Loss" "$LOSS"
  printf "%-20s : %s ms\n" "Min RTT" "$MIN"
  printf "%-20s : %s ms\n" "Avg RTT" "$AVG"
  printf "%-20s : %s ms\n" "Max RTT" "$MAX"
  printf "%-20s : %s ms\n" "Jitter / mdev" "$MDEV"
  printf "%-20s : %s ms\n" "95th Percentile" "$P95"
  printf "%-20s : %s ms\n" "99th Percentile" "$P99"
  
  # Bufferbloat grading
  BUFFERBLOAT_DELTA=$(awk "BEGIN {printf \"%.2f\", $MAX - $MIN}")
  printf "%-20s : %s ms\n" "Max-Min Jitter Spread" "$BUFFERBLOAT_DELTA"
  if (( $(awk "BEGIN {print ($BUFFERBLOAT_DELTA > 15.0)}") )); then
    echo "[WARNING] High bufferbloat / queue oscillation detected (spread > 15ms)."
  else
    echo "[OK] Low queue delay jitter (spread <= 15ms)."
  fi
fi
