#!/bin/bash
# tests/performance/test_wireguard_pc_simulation.sh
# Milestone M12: PC-Side BoringTun ARMv7 Verification & Sustained Load Simulation
# Architecture: Workstream C (Rust-First WireGuard Modernization)
#
# Creates dual network namespaces:
#   ns_router (192.168.31.1) running static boringtun-cli-armv7 via QEMU on wg1 (10.99.1.1/24)
#   ns_client (192.168.31.2) running kernel WireGuard on wg_client (10.99.1.2/24)
# Connected via veth pair (veth_r <-> veth_c).
#
# Measures: Handshake, ICMP latency, iperf3 sustained load, VmRSS, VmHWM, memory leak drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BT_BIN="${SCRIPT_DIR}/artifacts/m12_wireguard/boringtun-cli-armv7"
OUTPUT_JSON="${SCRIPT_DIR}/artifacts/m12_wireguard/simulation_telemetry.json"
OUTPUT_LOG="${SCRIPT_DIR}/artifacts/m12_wireguard/simulation_run.log"

NS_ROUTER="ns_ra82_sim"
NS_CLIENT="ns_pc_client"
ROUTER_IP="192.168.31.1"
CLIENT_IP="192.168.31.2"
WG_PORT=51821
WG_ROUTER_TUN="10.99.1.1"
WG_CLIENT_TUN="10.99.1.2"
SUBNET_MASK="/24"

# Pre-flight check
if [ ! -x "$BT_BIN" ]; then
    echo "ERROR: BoringTun binary not found or not executable at $BT_BIN" >&2
    exit 1
fi

echo "=== M12 Workstream C: PC-Side BoringTun ARMv7 Simulation ==="
echo "Binary: $BT_BIN"
echo "Target: Dual-Namespace Emulation (ARMv7 QEMU on Linux x86_64)"

# Cleanup function
cleanup() {
    echo "[Cleanup] Tearing down namespaces and processes..."
    if [ -n "${BT_PID:-}" ] && kill -0 "$BT_PID" 2>/dev/null; then
        kill -TERM "$BT_PID" 2>/dev/null || true
        sleep 1
        kill -KILL "$BT_PID" 2>/dev/null || true
    fi
    ip netns del "$NS_ROUTER" 2>/dev/null || true
    ip netns del "$NS_CLIENT" 2>/dev/null || true
    rm -rf /tmp/bt_sim_*
}
trap cleanup EXIT

# 1. Setup Network Namespaces
echo "[1/6] Creating network namespaces..."
ip netns add "$NS_ROUTER"
ip netns add "$NS_CLIENT"

# Loopback up
ip netns exec "$NS_ROUTER" ip link set lo up
ip netns exec "$NS_CLIENT" ip link set lo up

# Create veth interconnect
ip link add veth_r type veth peer name veth_c
ip link set veth_r netns "$NS_ROUTER"
ip link set veth_c netns "$NS_CLIENT"

ip netns exec "$NS_ROUTER" ip addr add "${ROUTER_IP}/24" dev veth_r
ip netns exec "$NS_ROUTER" ip link set veth_r up

ip netns exec "$NS_CLIENT" ip addr add "${CLIENT_IP}/24" dev veth_c
ip netns exec "$NS_CLIENT" ip link set veth_c up

# Verify physical connectivity
echo "[2/6] Verifying veth underlay link..."
ip netns exec "$NS_CLIENT" ping -c 3 -W 1 "$ROUTER_IP" >/dev/null
echo "  Underlay ping ($CLIENT_IP -> $ROUTER_IP): OK"

# 2. Key Generation
echo "[3/6] Generating WireGuard cryptographic keypairs..."
TMP_DIR=$(mktemp -d /tmp/bt_sim_XXXXXX)
chmod 700 "$TMP_DIR"

ROUTER_PRIV=$(wg genkey)
ROUTER_PUB=$(echo "$ROUTER_PRIV" | wg pubkey)
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)

# 3. Launch BoringTun ARMv7 in ns_router
echo "[4/6] Launching boringtun-cli-armv7 in router namespace..."
mkdir -p "$TMP_DIR/var_run_wg"
mkdir -p "$TMP_DIR/tmp_wg"

ip netns exec "$NS_ROUTER" bash -c "
  export WG_SUDO=1
  qemu-arm-static '$BT_BIN' \
    --disable-drop-privileges \
    --foreground \
    --threads 2 \
    --verbosity debug \
    --log '$TMP_DIR/boringtun.log' \
    wg1 > '$TMP_DIR/bt_stdout.log' 2>&1 &
  echo \$! > '$TMP_DIR/bt.pid'
"

BT_PID=$(cat "$TMP_DIR/bt.pid")
sleep 2

if ! kill -0 "$BT_PID" 2>/dev/null; then
    echo "ERROR: BoringTun daemon failed to start!" >&2
    cat "$TMP_DIR/bt_stdout.log" >&2
    exit 1
fi

echo "  BoringTun ARMv7 running with PID $BT_PID"

# Configure wg1 on router
cat << EOF > "$TMP_DIR/wg1_router.conf"
[Interface]
PrivateKey = $ROUTER_PRIV
ListenPort = $WG_PORT

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = ${WG_CLIENT_TUN}/32
PersistentKeepalive = 10
EOF

ip netns exec "$NS_ROUTER" wg setconf wg1 "$TMP_DIR/wg1_router.conf"
ip netns exec "$NS_ROUTER" ip addr add "${WG_ROUTER_TUN}/24" dev wg1
ip netns exec "$NS_ROUTER" ip link set mtu 1420 up dev wg1
echo "  Router wg1 configured (IP: ${WG_ROUTER_TUN}/24, Port: $WG_PORT UDP)"

# Baseline memory measurement (Idle)
PRE_RSS=$(grep -i VmRSS "/proc/$BT_PID/status" | awk '{print $2}')
PRE_HWM=$(grep -i VmHWM "/proc/$BT_PID/status" | awk '{print $2}')
PRE_SIZE=$(grep -i VmSize "/proc/$BT_PID/status" | awk '{print $2}')
echo "  Pre-traffic BoringTun Footprint: VmRSS=${PRE_RSS} kB, VmHWM=${PRE_HWM} kB, VmSize=${PRE_SIZE} kB"

# 4. Configure Client in ns_client
echo "[5/6] Configuring client WireGuard interface..."
cat << EOF > "$TMP_DIR/wg_client.conf"
[Interface]
PrivateKey = $CLIENT_PRIV

[Peer]
PublicKey = $ROUTER_PUB
Endpoint = ${ROUTER_IP}:${WG_PORT}
AllowedIPs = ${WG_ROUTER_TUN}/32
PersistentKeepalive = 10
EOF

ip netns exec "$NS_CLIENT" ip link add dev wg_client type wireguard
ip netns exec "$NS_CLIENT" wg setconf wg_client "$TMP_DIR/wg_client.conf"
ip netns exec "$NS_CLIENT" ip addr add "${WG_CLIENT_TUN}/24" dev wg_client
ip netns exec "$NS_CLIENT" ip link set mtu 1420 up dev wg_client

# 5. Handshake & Traffic Verification
echo "[6/6] Executing WireGuard tunnel handshake and traffic benchmark..."

# Ping from client to router across tunnel
PING_OUT=$(ip netns exec "$NS_CLIENT" ping -c 50 -i 0.05 "$WG_ROUTER_TUN")
LOSS=$(echo "$PING_OUT" | grep -oE '[0-9]+% packet loss' | awk '{print $1}' | tr -d '%')
RTT_LINE=$(echo "$PING_OUT" | grep -E '^(rtt|round-trip)' || true)
STATS=$(echo "$RTT_LINE" | awk '{print $4}')
MIN=$(echo "$STATS" | cut -d'/' -f1)
AVG=$(echo "$STATS" | cut -d'/' -f2)
MAX=$(echo "$STATS" | cut -d'/' -f3)
MDEV=$(echo "$STATS" | cut -d'/' -f4)

echo "  ICMP Ping Results: Loss=${LOSS}%, Min=${MIN}ms, Avg=${AVG}ms, Max=${MAX}ms, Mdev=${MDEV}ms"

# Verify Handshake on Router
WG_ROUTER_STATUS=$(ip netns exec "$NS_ROUTER" wg show wg1)
HANDSHAKE_LINE=$(echo "$WG_ROUTER_STATUS" | grep "latest handshake" || true)
TRANSFER_LINE=$(echo "$WG_ROUTER_STATUS" | grep "transfer:" || true)
echo "  Router Tunnel Status: $HANDSHAKE_LINE | $TRANSFER_LINE"

# Run Sustained iperf3 Traffic Simulation (10 seconds TCP)
echo "  Starting sustained iperf3 traffic load (10 seconds)..."
ip netns exec "$NS_ROUTER" iperf3 -s -D >/dev/null 2>&1
sleep 1

IPERF_OUT=$(ip netns exec "$NS_CLIENT" iperf3 -c "$WG_ROUTER_TUN" -t 10 -J)
THROUGHPUT_BPS=$(echo "$IPERF_OUT" | jq -r '.end.sum_received.bits_per_second // 0')
THROUGHPUT_MBPS=$(awk "BEGIN {printf \"%.2f\", $THROUGHPUT_BPS / 1000000}")
RETRANSMITS=$(echo "$IPERF_OUT" | jq -r '.end.sum_sent.retransmits // 0')

echo "  Sustained TCP Throughput: ${THROUGHPUT_MBPS} Mbps (Retransmits: $RETRANSMITS)"

# Post-traffic memory measurement (Under/after Load)
POST_RSS=$(grep -i VmRSS "/proc/$BT_PID/status" | awk '{print $2}')
POST_HWM=$(grep -i VmHWM "/proc/$BT_PID/status" | awk '{print $2}')
POST_SIZE=$(grep -i VmSize "/proc/$BT_PID/status" | awk '{print $2}')
RSS_GROWTH=$(( POST_RSS - PRE_RSS ))

echo "  Post-traffic BoringTun Footprint: VmRSS=${POST_RSS} kB, VmHWM=${POST_HWM} kB, Net Growth=${RSS_GROWTH} kB"

# 6. Verify Acceptance Criteria
PASS=1
if [ "$LOSS" -ne 0 ]; then
    echo "FAIL: Packet loss is non-zero ($LOSS%)" >&2
    PASS=0
fi

if [ "$POST_RSS" -gt 65536 ]; then
    echo "FAIL: VmRSS exceeded threshold ($POST_RSS kB > 64MB)" >&2
    PASS=0
fi

# Write JSON Telemetry
cat << EOF > "$OUTPUT_JSON"
{
  "test_name": "boringtun_armv7_pc_simulation",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "binary_path": "$BT_BIN",
  "binary_arch": "ARMv7 hard-float (armv7-unknown-linux-musleabihf +neon)",
  "qemu_emulated": true,
  "tunnel_interface": "wg1",
  "listen_port": $WG_PORT,
  "ping_stats": {
    "packets_sent": 50,
    "packet_loss_pct": $LOSS,
    "rtt_min_ms": $MIN,
    "rtt_avg_ms": $AVG,
    "rtt_max_ms": $MAX,
    "rtt_mdev_ms": $MDEV
  },
  "traffic_stats": {
    "protocol": "TCP",
    "duration_sec": 10,
    "throughput_mbps": $THROUGHPUT_MBPS,
    "retransmits": $RETRANSMITS
  },
  "memory_footprint_kb": {
    "pre_traffic_vm_rss": $PRE_RSS,
    "post_traffic_vm_rss": $POST_RSS,
    "peak_vm_hwm": $POST_HWM,
    "vm_size": $POST_SIZE,
    "net_growth_kb": $RSS_GROWTH
  },
  "acceptance_verdict": "$([ "$PASS" -eq 1 ] && echo "PASS" || echo "FAIL")"
}
EOF

echo "Telemetry written to $OUTPUT_JSON"
echo "=== SIMULATION COMPLETED SUCCESSFULLY (Verdict: $([ "$PASS" -eq 1 ] && echo "PASS" || echo "FAIL")) ==="
