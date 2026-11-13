#!/bin/sh
# performance/wireguard_rust/benchmark_wg0_vs_wg1.sh
# Milestone M12.6 Priority D: Live Comparative Benchmark Tool (Go wg0 vs Rust wg1)
# Target: Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 armv7l)
#
# Boundaries:
# - Strictly read-only analysis of running processes and tunnel interfaces
# - Leaves production wg0 100% active and untouched
# - Outputs side-by-side memory, latency, and throughput comparison

set -u

OUTPUT_JSON="${OUTPUT_JSON:-/tmp/wg_comparison_benchmark.json}"
PROC_ROOT="${PROC_ROOT:-/proc}"
WG1_PID_FILE="${WG1_PID_FILE:-/tmp/wg1.pid}"

log() {
    echo "[benchmark-wg] $*"
}

# 1. Inspect Go Daemon (wg0) -- never fabricates baseline numbers if /proc unreadable
GO_PID=$(pidof wg_server 2>/dev/null || pgrep -f "/data/wg_server" 2>/dev/null || echo "")
GO_STATUS="UNAVAILABLE"
GO_RSS="null"
GO_HWM="null"
GO_ANON="null"
GO_SIZE="null"
if [ -n "$GO_PID" ] && [ -f "${PROC_ROOT}/${GO_PID}/status" ]; then
    _rss=$(grep -i VmRSS "${PROC_ROOT}/${GO_PID}/status" | awk '{print $2}' || echo "")
    _hwm=$(grep -i VmHWM "${PROC_ROOT}/${GO_PID}/status" | awk '{print $2}' || echo "")
    _anon=$(grep -i RssAnon "${PROC_ROOT}/${GO_PID}/status" | awk '{print $2}' || echo "")
    _size=$(grep -i VmSize "${PROC_ROOT}/${GO_PID}/status" | awk '{print $2}' || echo "")
    if [ -n "$_rss" ] && [ -n "$_hwm" ] && [ -n "$_size" ]; then
        GO_STATUS="LIVE"
        GO_RSS="$_rss"
        GO_HWM="$_hwm"
        GO_ANON="${_anon:-null}"
        GO_SIZE="$_size"
    else
        GO_PID="UNAVAILABLE"
    fi
else
    GO_PID="UNAVAILABLE"
fi

# 2. Inspect Rust Daemon (wg1)
RUST_PID=$(cat "$WG1_PID_FILE" 2>/dev/null || pidof boringtun-cli-armv7 2>/dev/null || echo "")
RUST_STATUS="UNAVAILABLE"
RUST_RSS="null"
RUST_HWM="null"
RUST_ANON="null"
RUST_SIZE="null"
if [ -n "$RUST_PID" ] && [ -f "${PROC_ROOT}/${RUST_PID}/status" ]; then
    _rrss=$(grep -i VmRSS "${PROC_ROOT}/${RUST_PID}/status" | awk '{print $2}' || echo "")
    _rhwm=$(grep -i VmHWM "${PROC_ROOT}/${RUST_PID}/status" | awk '{print $2}' || echo "")
    _ranon=$(grep -i RssAnon "${PROC_ROOT}/${RUST_PID}/status" | awk '{print $2}' || echo "")
    _rsize=$(grep -i VmSize "${PROC_ROOT}/${RUST_PID}/status" | awk '{print $2}' || echo "")
    if [ -n "$_rrss" ] && [ -n "$_rhwm" ] && [ -n "$_rsize" ]; then
        RUST_STATUS="LIVE"
        RUST_RSS="$_rrss"
        RUST_HWM="$_rhwm"
        RUST_ANON="${_ranon:-null}"
        RUST_SIZE="$_rsize"
    else
        RUST_PID="UNAVAILABLE"
    fi
else
    RUST_PID="UNAVAILABLE"
fi

# 3. Calculate Memory Delta only when BOTH live /proc readings succeeded
RAM_SAVED_KB="null"
RAM_SAVED_PCT="null"
if [ "$GO_STATUS" = "LIVE" ] && [ "$RUST_STATUS" = "LIVE" ] && [ "$GO_RSS" -gt 0 ] 2>/dev/null; then
    RAM_SAVED_KB=$(( GO_RSS - RUST_RSS ))
    RAM_SAVED_PCT=$(( (RAM_SAVED_KB * 100) / GO_RSS ))
fi

# 4. Latency / RTT Measurement (if interfaces are UP)
measure_ping() {
    target_ip="$1"
    if ping -c 1 -W 1 "$target_ip" >/dev/null 2>&1; then
        res=$(ping -c 20 -i 0.05 -W 1 "$target_ip" 2>/dev/null || true)
        avg=$(echo "$res" | grep -E '^(rtt|round-trip)' | awk '{print $4}' | cut -d'/' -f2 || echo "N/A")
        loss=$(echo "$res" | sed -n 's/.*, *\([0-9]*\)\(\.[0-9]*\)*% packet loss.*/\1/p' || echo "N/A")
        echo "${avg}ms (Loss: ${loss}%)"
    else
        echo "UNREACHABLE"
    fi
}

WG0_LATENCY=$(measure_ping "10.99.0.1")
WG1_LATENCY=$(measure_ping "10.99.1.1")

# 5. Render Comparison Table
echo "=========================================================================================="
echo "          WIREGUARD IMPLEMENTATION BENCHMARK: GO (wg0) vs RUST BORINGTUN (wg1)            "
echo "=========================================================================================="
printf "%-25s | %-25s | %-25s\n" "Metric" "Go Daemon (wg0)" "Rust BoringTun (wg1)"
echo "--------------------------+---------------------------+-----------------------------------"
printf "%-25s | %-25s | %-25s\n" "Interface" "wg0" "wg1"
printf "%-25s | %-25s | %-25s\n" "Listening Port" "51820 UDP" "51821 UDP"
printf "%-25s | %-25s | %-25s\n" "Subnet" "10.99.0.1/24" "10.99.1.1/24"
printf "%-25s | %-25s | %-25s\n" "Process PID" "$GO_PID" "$RUST_PID"
printf "%-25s | %-25s | %-25s\n" "Resident Memory (VmRSS)" "${GO_RSS} kB" "${RUST_RSS} kB"
printf "%-25s | %-25s | %-25s\n" "Peak Resident (VmHWM)" "${GO_HWM} kB" "${RUST_HWM} kB"
printf "%-25s | %-25s | %-25s\n" "Private Anonymous RAM" "${GO_ANON} kB" "${RUST_ANON} kB"
printf "%-25s | %-25s | %-25s\n" "Virtual Size (VmSize)" "${GO_SIZE} kB" "${RUST_SIZE} kB"
printf "%-25s | %-25s | %-25s\n" "Round-Trip Latency" "$WG0_LATENCY" "$WG1_LATENCY"
echo "--------------------------+---------------------------+-----------------------------------"
if [ "$RAM_SAVED_KB" -gt 0 ]; then
    printf "%-25s | %-53s\n" "Net Physical RAM Saved" "${RAM_SAVED_KB} kB (${RAM_SAVED_PCT}% reduction)"
fi
echo "=========================================================================================="

# 6. Output Telemetry JSON
cat << EOF > "$OUTPUT_JSON"
{
  "benchmark_name": "wg0_go_vs_wg1_rust",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)",
  "go_daemon": {
    "interface": "wg0",
    "port": 51820,
    "pid": "$GO_PID",
    "vm_rss_kb": $GO_RSS,
    "vm_hwm_kb": $GO_HWM,
    "rss_anon_kb": $GO_ANON,
    "vm_size_kb": $GO_SIZE,
    "latency": "$WG0_LATENCY"
  },
  "rust_daemon": {
    "interface": "wg1",
    "port": 51821,
    "pid": "$RUST_PID",
    "vm_rss_kb": $RUST_RSS,
    "vm_hwm_kb": $RUST_HWM,
    "rss_anon_kb": $RUST_ANON,
    "vm_size_kb": $RUST_SIZE,
    "latency": "$WG1_LATENCY"
  },
  "comparison": {
    "net_ram_saved_kb": $RAM_SAVED_KB,
    "ram_reduction_pct": $RAM_SAVED_PCT
  }
}
EOF

log "Telemetry written to $OUTPUT_JSON"
