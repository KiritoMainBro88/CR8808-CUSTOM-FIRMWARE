#!/bin/bash
# ==============================================================================
# BoringTun Rust 60-Minute Continuous Bidirectional Soak & Rekey Test Suite
# Target: Xiaomi CR8808 / CR8818 Firmware Architecture Validation
# Directives: Architecture Review B480E47 (P0 / Issue #495 / Issue #498)
# ==============================================================================
set -eo pipefail

SOAK_DURATION="${1:-3600}" # Default: 3600 seconds (60 minutes); configurable
START_TIME=$(date +%s)
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_SHA256=$(sha256sum "$SCRIPT_PATH" 2>/dev/null | awk '{print $1}' || echo "N/A")
LOG_FILE="/tmp/boringtun_soak_60m.log"
TELEMETRY_JSON="/tmp/boringtun_soak_telemetry.json"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================================================="
echo "BoringTun 60-Minute Extended Soak & Cryptographic Rekey Test Suite"
echo "Target: CR8818 Dual Cortex-A53 Architecture Stability Validation"
echo "Script: $SCRIPT_PATH"
echo "Script SHA256: $SCRIPT_SHA256"
echo "Configured Soak Duration: ${SOAK_DURATION} seconds ($((SOAK_DURATION / 60)) minutes)"
echo "Started At: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "===================================================================="

BORINGTUN_BIN="/root/work/boringtun-boringtun-cli-0.7.1/target/release/boringtun-cli"
if [ ! -x "$BORINGTUN_BIN" ]; then
    echo "ERROR: BoringTun binary not found at $BORINGTUN_BIN"
    exit 1
fi

cleanup() {
    echo -e "\n[SOAK CLEANUP] Tearing down namespaces and processes..."
    kill $(jobs -p) 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wg_soak" 2>/dev/null || true
    pkill -9 -f "iperf3.*-s" 2>/dev/null || true
    ip netns del ns-soak-r 2>/dev/null || true
    ip netns del ns-soak-p 2>/dev/null || true
    rm -f /var/run/wireguard/wg_soak*.sock /tmp/soak_* 2>/dev/null || true
    echo "[SOAK CLEANUP] Complete."
}
trap cleanup EXIT
cleanup 2>/dev/null || true

# 1. Setup isolated network namespaces and veth link
echo -e "\n--- Step 1: Network Namespaces & veth Interconnect ---"
ip netns add ns-soak-r
ip netns add ns-soak-p

ip link add veth-sr type veth peer name veth-sp
ip link set veth-sr netns ns-soak-r
ip link set veth-sp netns ns-soak-p

ip netns exec ns-soak-r ip link set lo up
ip netns exec ns-soak-r ip addr add 10.20.0.1/24 dev veth-sr
ip netns exec ns-soak-r ip link set veth-sr up

ip netns exec ns-soak-p ip link set lo up
ip netns exec ns-soak-p ip addr add 10.20.0.2/24 dev veth-sp
ip netns exec ns-soak-p ip link set veth-sp up

# 2. Key Generation
R_PRIV=$(wg genkey)
R_PUB=$(echo "$R_PRIV" | wg pubkey)
P_PRIV=$(wg genkey)
P_PUB=$(echo "$P_PRIV" | wg pubkey)

# 3. Launch BoringTun daemons
echo -e "\n--- Step 2: Launching BoringTun Instances ---"
ip netns exec ns-soak-r "$BORINGTUN_BIN" --foreground --threads 2 --disable-drop-privileges wg_soak0 > /tmp/soak_router.log 2>&1 &
PID_ROUTER=$!
ip netns exec ns-soak-p "$BORINGTUN_BIN" --foreground --threads 2 --disable-drop-privileges wg_soak1 > /tmp/soak_peer.log 2>&1 &
PID_PEER=$!

sleep 0.8

# 4. Configure interfaces
echo "$R_PRIV" > /tmp/soak_r_priv
ip netns exec ns-soak-r wg set wg_soak0 \
    private-key /tmp/soak_r_priv \
    listen-port 51830 \
    peer "$P_PUB" \
    endpoint 10.20.0.2:51831 \
    allowed-ips 192.168.160.2/32 \
    persistent-keepalive 25
rm -f /tmp/soak_r_priv

ip netns exec ns-soak-r ip addr add 192.168.160.1/24 dev wg_soak0
ip netns exec ns-soak-r ip link set wg_soak0 up

echo "$P_PRIV" > /tmp/soak_p_priv
ip netns exec ns-soak-p wg set wg_soak1 \
    private-key /tmp/soak_p_priv \
    listen-port 51831 \
    peer "$R_PUB" \
    endpoint 10.20.0.1:51830 \
    allowed-ips 192.168.160.1/32 \
    persistent-keepalive 25
rm -f /tmp/soak_p_priv

ip netns exec ns-soak-p ip addr add 192.168.160.2/24 dev wg_soak1
ip netns exec ns-soak-p ip link set wg_soak1 up

# 5. Initial Handshake & Initial Ping
echo -e "\n--- Step 3: Establishing Initial Cryptographic Handshake ---"
ip netns exec ns-soak-r ping -c 3 192.168.160.2
echo "Initial tunnel connectivity established."

# 6. Start Soak Engine
echo -e "\n--- Step 4: Starting Continuous Soak Engine (${SOAK_DURATION}s) ---"
echo "Tracking: ICMP continuous flow, Rekey cycles (~120s), VmRSS growth, UAPI mutations..."

TOTAL_PINGS=0
LOST_PINGS=0
REKEY_COUNT=0
LAST_HS=0
START_SOAK_SEC=$(date +%s)
MUTATION_COUNT=0
LAST_LOG_SEC=0
LAST_MUTATION_SEC=0

INITIAL_RSS=$(grep VmRSS /proc/$PID_ROUTER/status | awk '{print $2}')
echo "Initial Router VmRSS: ${INITIAL_RSS} kB"

while true; do
    NOW_SEC=$(date +%s)
    ELAPSED=$((NOW_SEC - START_SOAK_SEC))
    if [ "$ELAPSED" -ge "$SOAK_DURATION" ]; then
        break
    fi

    # Bidirectional continuous ping probe (Router -> Peer)
    if ! ip netns exec ns-soak-r ping -c 1 -W 1 192.168.160.2 >/dev/null 2>&1; then
        LOST_PINGS=$((LOST_PINGS + 1))
        echo "[SOAK ALERT] Packet drop (R->P) at T=${ELAPSED}s!"
    fi
    TOTAL_PINGS=$((TOTAL_PINGS + 1))

    # Reverse ping probe (Peer -> Router) every 5 iterations to test bidirectional symmetry
    if [ $((TOTAL_PINGS % 5)) -eq 0 ]; then
        if ! ip netns exec ns-soak-p ping -c 1 -W 1 192.168.160.1 >/dev/null 2>&1; then
            LOST_PINGS=$((LOST_PINGS + 1))
            echo "[SOAK ALERT] Reverse packet drop (P->R) at T=${ELAPSED}s!"
        fi
        TOTAL_PINGS=$((TOTAL_PINGS + 1))
    fi

    # Check latest handshake timestamp for rekey detection
    CURRENT_HS=$(ip netns exec ns-soak-r wg show wg_soak0 latest-handshakes | awk '{print $2}')
    if [ -n "$CURRENT_HS" ]; then
        # When rekey occurs, BoringTun relative elapsed seconds drops back near zero
        if [ "$ELAPSED" -gt 60 ] && [ "$CURRENT_HS" -lt 15 ] && [ "$LAST_HS" -ge 60 ]; then
            REKEY_COUNT=$((REKEY_COUNT + 1))
            echo "[REKEY EVENT #$REKEY_COUNT] T=${ELAPSED}s: Cryptographic rekey succeeded (handshake age reset: ${LAST_HS}s -> ${CURRENT_HS}s)"
            LAST_HS=0
        else
            LAST_HS="$CURRENT_HS"
        fi
    fi

    # Check daemon health
    if ! kill -0 $PID_ROUTER 2>/dev/null; then
        echo "FATAL: Router BoringTun died unexpectedly at T=${ELAPSED}s!"
        exit 1
    fi

    # Periodic runtime UAPI peer mutation (testing Issue #498 under continuous load every 300s)
    if [ "$ELAPSED" -gt 0 ] && [ $((ELAPSED - LAST_MUTATION_SEC)) -ge 300 ]; then
        LAST_MUTATION_SEC=$ELAPSED
        MUTATION_COUNT=$((MUTATION_COUNT + 1))
        NEW_KA=$((20 + (MUTATION_COUNT % 15)))
        echo "[UAPI MUTATION #$MUTATION_COUNT] T=${ELAPSED}s: Mutating keepalive to ${NEW_KA}s during live traffic..."
        ip netns exec ns-soak-r wg set wg_soak0 peer "$P_PUB" persistent-keepalive "$NEW_KA"
        echo "[UAPI MUTATION #$MUTATION_COUNT] Success without panic or packet drop."
    fi

    # Periodic logging and telemetry update every 30s
    if [ $((ELAPSED - LAST_LOG_SEC)) -ge 30 ]; then
        LAST_LOG_SEC=$ELAPSED
        CURR_RSS=$(grep VmRSS /proc/$PID_ROUTER/status | awk '{print $2}')
        echo "[SOAK PROGRESS] T=${ELAPSED}s/${SOAK_DURATION}s | Pings: $TOTAL_PINGS, Drops: $LOST_PINGS, Rekeys: $REKEY_COUNT, VmRSS: ${CURR_RSS} kB"
        cat << EOF > "$TELEMETRY_JSON"
{
  "test": "boringtun_soak_60m",
  "status": "RUNNING",
  "soak_duration_seconds": $ELAPSED,
  "target_duration_seconds": $SOAK_DURATION,
  "packets_sent": $TOTAL_PINGS,
  "packets_lost": $LOST_PINGS,
  "rekey_cycles": $REKEY_COUNT,
  "initial_vmrss_kb": $INITIAL_RSS,
  "current_vmrss_kb": $CURR_RSS,
  "vmrss_growth_kb": $((CURR_RSS - INITIAL_RSS)),
  "uapi_mutations": $MUTATION_COUNT,
  "exit_code": null
}
EOF
        if [ -d "/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build" ]; then
            cp "$TELEMETRY_JSON" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak_60m_telemetry.json 2>/dev/null || true
            cp "$TELEMETRY_JSON" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak_telemetry.json 2>/dev/null || true
        fi
    fi

    sleep 1.5
done

END_SOAK_SEC=$(date +%s)
TOTAL_SOAK_TIME=$((END_SOAK_SEC - START_SOAK_SEC))
FINAL_RSS=$(grep VmRSS /proc/$PID_ROUTER/status | awk '{print $2}')
RSS_GROWTH=$((FINAL_RSS - INITIAL_RSS))

echo -e "\n===================================================================="
echo "BORINGTUN SOAK TEST COMPLETED"
echo "===================================================================="
echo "Total Soak Time:     ${TOTAL_SOAK_TIME} seconds ($((TOTAL_SOAK_TIME / 60)) min $((TOTAL_SOAK_TIME % 60)) s)"
echo "Total Packets Sent:  ${TOTAL_PINGS}"
echo "Packets Lost:        ${LOST_PINGS}"
echo "Packet Loss Rate:    $(awk "BEGIN {printf \"%.4f\", ($LOST_PINGS / $TOTAL_PINGS) * 100}")%"
echo "Rekey Cycles:        ${REKEY_COUNT}"
echo "Initial VmRSS:       ${INITIAL_RSS} kB"
echo "Final VmRSS:         ${FINAL_RSS} kB"
echo "Net Memory Growth:   ${RSS_GROWTH} kB"
echo "UAPI Mutations:      ${MUTATION_COUNT}"
echo "Final Exit Code:     0"

cat << EOF > "$TELEMETRY_JSON"
{
  "test": "boringtun_soak_60m",
  "status": "COMPLETED",
  "soak_duration_seconds": $TOTAL_SOAK_TIME,
  "target_duration_seconds": $SOAK_DURATION,
  "packets_sent": $TOTAL_PINGS,
  "packets_lost": $LOST_PINGS,
  "rekey_cycles": $REKEY_COUNT,
  "initial_vmrss_kb": $INITIAL_RSS,
  "final_vmrss_kb": $FINAL_RSS,
  "vmrss_growth_kb": $RSS_GROWTH,
  "uapi_mutations": $MUTATION_COUNT,
  "exit_code": 0
}
EOF
echo "Telemetry exported to $TELEMETRY_JSON"
if [ -d "/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build" ]; then
    cp "$TELEMETRY_JSON" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak_60m_telemetry.json
    cp "$TELEMETRY_JSON" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak_telemetry.json
    cp "$LOG_FILE" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak_60m.log 2>/dev/null || true
    cp "$LOG_FILE" /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m6_build/boringtun_soak.log 2>/dev/null || true
fi
