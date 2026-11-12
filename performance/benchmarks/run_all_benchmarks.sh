#!/bin/bash
# performance/benchmarks/run_all_benchmarks.sh
# Milestone M12: Master Benchmark Suite Orchestrator
# Runs softirq profiling, memory accounting, and network latency benchmarks.
#
# Usage:
#   ./run_all_benchmarks.sh [--duration <sec>] [--output-json <file>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURATION=5
JSON_OUT=""
ROUTER_IP="192.168.31.1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --output-json|-o)
      JSON_OUT="$2"
      shift 2
      ;;
    --target|-t)
      ROUTER_IP="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--duration <sec>] [--output-json <file>] [--target <ip>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "================================================================================"
echo "          RA82 PERFORMANCE BENCHMARK SUITE - MILESTONE M12"
echo "================================================================================"
echo "Target Router : $ROUTER_IP"
echo "Sample Window : ${DURATION}s"
echo "Date / Time   : $(date)"
echo ""

# 1. SoftIRQ Profiler
echo "[1/3] Running SoftIRQ & Interrupt Imbalance Profiler..."
bash "${SCRIPT_DIR}/softirq_profiler.sh" --duration "$DURATION" --remote "$ROUTER_IP"
echo ""

# 2. Memory Accounting Profiler
echo "[2/3] Running RAM Allocation & Slab Fragmentation Profiler..."
bash "${SCRIPT_DIR}/memory_profiler.sh" --remote "$ROUTER_IP"
echo ""

# 3. Network Latency & Bufferbloat Suite
echo "[3/3] Running ICMP Latency & Jitter Suite..."
bash "${SCRIPT_DIR}/network_latency_suite.sh" --target "$ROUTER_IP" --count 30
echo ""

# 4. Optional WireGuard Benchmark
if [ -n "${SSHPASS:-}" ]; then
  echo "[4/3 Bonus] Inspecting Active WireGuard wg0 Status..."
  bash "${SCRIPT_DIR}/wireguard_benchmark.sh" --interface wg0 --target-ip 10.99.0.1 || true
  echo ""
fi

# Generate Combined JSON if requested
if [ -n "$JSON_OUT" ]; then
  echo "Exporting structured benchmark telemetry to $JSON_OUT..."
  {
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"target\": \"$ROUTER_IP\","
    echo "  \"softirq\": $(bash "${SCRIPT_DIR}/softirq_profiler.sh" --duration "$DURATION" --remote "$ROUTER_IP" --json),"
    echo "  \"memory\": $(bash "${SCRIPT_DIR}/memory_profiler.sh" --remote "$ROUTER_IP" --json),"
    echo "  \"latency\": $(bash "${SCRIPT_DIR}/network_latency_suite.sh" --target "$ROUTER_IP" --count 20 --json)"
    echo "}"
  } > "$JSON_OUT"
  echo "Export complete: $(wc -l < "$JSON_OUT") lines."
fi

echo "================================================================================"
echo "All benchmarks completed successfully."
echo "================================================================================"
