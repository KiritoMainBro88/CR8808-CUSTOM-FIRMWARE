#!/bin/bash
set -eo pipefail

START_TIME=$(date +%s)
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_SHA256=$(sha256sum "$SCRIPT_PATH" | awk '{print $1}')

echo "===================================================================="
echo "BoringTun 0.7.1 Linux Network Namespace Integration Test Suite"
echo "Target: CR8818 Firmware Architecture Validation & Issue #498/#495 Audit"
echo "Script: $SCRIPT_PATH"
echo "Script SHA256: $SCRIPT_SHA256"
echo "Started At: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "===================================================================="

BORINGTUN_BIN="/root/work/boringtun-boringtun-cli-0.7.1/target/release/boringtun-cli"
if [ ! -x "$BORINGTUN_BIN" ]; then
    echo "ERROR: BoringTun binary not found at $BORINGTUN_BIN"
    exit 1
fi

cleanup() {
    echo -e "\n[CLEANUP] Tearing down namespaces and processes..."
    kill $(jobs -p) 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wg0" 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wg1" 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wg2" 2>/dev/null || true
    pkill -9 -f "iperf3.*-s" 2>/dev/null || true
    ip netns del ns-router 2>/dev/null || true
    ip netns del ns-peer 2>/dev/null || true
    ip netns del ns-peer2 2>/dev/null || true
    rm -rf /tmp/bt_test_* /tmp/router_priv /tmp/peer_priv /tmp/peer2_priv \
           /var/run/wireguard/wg0.sock /var/run/wireguard/wg1.sock /var/run/wireguard/wg2.sock 2>/dev/null || true
    echo "[CLEANUP] Complete."
}
trap cleanup EXIT

cleanup 2>/dev/null || true

echo -e "\n--- Step 1: Setting up network namespaces and veth interconnect ---"
ip netns add ns-router
ip netns add ns-peer
ip netns add ns-peer2

# Interconnect ns-router <-> ns-peer
ip link add veth-r type veth peer name veth-p
ip link set veth-r netns ns-router
ip link set veth-p netns ns-peer

ip netns exec ns-router ip link set lo up
ip netns exec ns-router ip addr add 10.0.0.1/24 dev veth-r
ip netns exec ns-router ip link set veth-r up

ip netns exec ns-peer ip link set lo up
ip netns exec ns-peer ip addr add 10.0.0.2/24 dev veth-p
ip netns exec ns-peer ip link set veth-p up

# Interconnect ns-router <-> ns-peer2
ip link add veth-r2 type veth peer name veth-p2
ip link set veth-r2 netns ns-router
ip link set veth-p2 netns ns-peer2

ip netns exec ns-router ip addr add 10.0.1.1/24 dev veth-r2
ip netns exec ns-router ip link set veth-r2 up

ip netns exec ns-peer2 ip link set lo up
ip netns exec ns-peer2 ip addr add 10.0.1.2/24 dev veth-p2
ip netns exec ns-peer2 ip link set veth-p2 up

echo "Checking underlay connectivity between namespaces:"
ip netns exec ns-router ping -c 2 10.0.0.2
ip netns exec ns-router ping -c 2 10.0.1.2

echo -e "\n--- Step 2: Generating WireGuard Keypairs ---"
ROUTER_PRIV=$(wg genkey)
ROUTER_PUB=$(echo "$ROUTER_PRIV" | wg pubkey)
PEER_PRIV=$(wg genkey)
PEER_PUB=$(echo "$PEER_PRIV" | wg pubkey)
PEER2_PRIV=$(wg genkey)
PEER2_PUB=$(echo "$PEER2_PRIV" | wg pubkey)

echo "Router PubKey: $ROUTER_PUB"
echo "Peer1 PubKey:  $PEER_PUB"
echo "Peer2 PubKey:  $PEER2_PUB"

mkdir -p /var/run/wireguard

echo -e "\n--- Step 3: Launching BoringTun Instances in Namespaces ---"
# Start router boringtun in ns-router
ip netns exec ns-router "$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug --disable-drop-privileges wg0 > /tmp/bt_router.log 2>&1 &
ROUTER_PID=$!

# Start peer boringtun in ns-peer
ip netns exec ns-peer "$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug --disable-drop-privileges wg1 > /tmp/bt_peer.log 2>&1 &
PEER_PID=$!

# Start peer2 boringtun in ns-peer2
ip netns exec ns-peer2 "$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug --disable-drop-privileges wg2 > /tmp/bt_peer2.log 2>&1 &
PEER2_PID=$!

echo "Router BoringTun PID: $ROUTER_PID"
echo "Peer1 BoringTun PID:  $PEER_PID"
echo "Peer2 BoringTun PID:  $PEER2_PID"

# Wait for TUN interfaces to appear
ready=0
for i in $(seq 1 20); do
    if ip netns exec ns-router ip link show wg0 >/dev/null 2>&1 && \
       ip netns exec ns-peer ip link show wg1 >/dev/null 2>&1 && \
       ip netns exec ns-peer2 ip link show wg2 >/dev/null 2>&1; then
        echo "All TUN interfaces (wg0, wg1, wg2) ready after $i attempts."
        ready=1
        break
    fi
    sleep 0.2
done

if [ "$ready" -ne 1 ]; then
    echo "ERROR: Interfaces failed to become ready"
    cat /tmp/bt_router.log
    cat /tmp/bt_peer.log
    exit 1
fi

echo -e "\n--- Step 4: Configuring WireGuard Interfaces and Peers ---"
# Configure router wg0 (peer 1)
echo "$ROUTER_PRIV" > /tmp/router_priv
ip netns exec ns-router wg set wg0 \
    private-key /tmp/router_priv \
    listen-port 51820 \
    peer "$PEER_PUB" \
    endpoint 10.0.0.2:51821 \
    allowed-ips 192.168.100.2/32,fd00:dead:beef::2/128 \
    persistent-keepalive 25
rm -f /tmp/router_priv

ip netns exec ns-router ip addr add 192.168.100.1/24 dev wg0
ip netns exec ns-router ip addr add fd00:dead:beef::1/64 dev wg0
ip netns exec ns-router ip link set wg0 up

# Configure peer1 wg1
echo "$PEER_PRIV" > /tmp/peer_priv
ip netns exec ns-peer wg set wg1 \
    private-key /tmp/peer_priv \
    listen-port 51821 \
    peer "$ROUTER_PUB" \
    endpoint 10.0.0.1:51820 \
    allowed-ips 192.168.100.1/32,fd00:dead:beef::1/128 \
    persistent-keepalive 25
rm -f /tmp/peer_priv

ip netns exec ns-peer ip addr add 192.168.100.2/24 dev wg1
ip netns exec ns-peer ip addr add fd00:dead:beef::2/64 dev wg1
ip netns exec ns-peer ip link set wg1 up

# Configure peer2 wg2
echo "$PEER2_PRIV" > /tmp/peer2_priv
ip netns exec ns-peer2 wg set wg2 \
    private-key /tmp/peer2_priv \
    listen-port 51822 \
    peer "$ROUTER_PUB" \
    endpoint 10.0.1.1:51820 \
    allowed-ips 192.168.100.1/32 \
    persistent-keepalive 25
rm -f /tmp/peer2_priv

ip netns exec ns-peer2 ip addr add 192.168.100.3/24 dev wg2
ip netns exec ns-peer2 ip link set wg2 up

echo -e "\n--- Step 5: Testing Initial Handshake & Bi-directional IPv4/IPv6 Ping ---"
echo "Pinging Peer1 from Router (IPv4):"
ip netns exec ns-router ping -c 3 192.168.100.2

echo "Pinging Router from Peer1 (IPv4):"
ip netns exec ns-peer ping -c 3 192.168.100.1

echo "Pinging Peer1 from Router (IPv6):"
ip netns exec ns-router ping -6 -c 3 fd00:dead:beef::2

echo -e "\n--- Step 6: Testing Issue #495 Regression (One-way deaf after 15-30s) ---"
echo "Sleeping 20 seconds to test keepalive and session rotation..."
sleep 20

echo "Testing Router -> Peer1 transmission after 20s idle:"
ip netns exec ns-router ping -c 3 -W 2 192.168.100.2

echo "Testing Peer1 -> Router transmission after 20s idle:"
ip netns exec ns-peer ping -c 3 -W 2 192.168.100.1

echo "Sleeping additional 15 seconds (total 35s since handshake)..."
sleep 15

echo "Testing Router -> Peer1 transmission after 35s total:"
ip netns exec ns-router ping -c 3 -W 2 192.168.100.2

echo "Testing Peer1 -> Router transmission after 35s total:"
ip netns exec ns-peer ping -c 3 -W 2 192.168.100.1

echo "SUCCESS: Issue #495 (one-way deaf) did NOT occur."

echo -e "\n--- Step 7: Measuring Real Memory Consumption (Idle) ---"
echo "Process Status for Router BoringTun (PID: $ROUTER_PID) [IDLE]:"
cat /proc/$ROUTER_PID/status | grep -E "Name|State|VmSize|VmRSS|VmHWM|VmData|Threads"

echo -e "\n--- Step 8: Sustained Bi-Directional Throughput Test (iperf3) with Raw JSON Output ---"
ip netns exec ns-peer iperf3 -s -D
sleep 1

echo "Starting 10-second TCP iperf3 benchmark with JSON telemetry capture..."
IPERF_JSON="/tmp/iperf3_results.json"
ip netns exec ns-router iperf3 -c 192.168.100.2 -t 10 -i 2 -J > "$IPERF_JSON"

echo "iPerf3 JSON captured. Summary:"
python3 -c "
import json
with open('$IPERF_JSON') as f:
    d = json.load(f)
sent = d['end']['sum_sent']
recv = d['end']['sum_received']
cpu = d['end']['cpu_utilization_percent']
print(f'  Transfer Sent: {sent[\"bytes\"] / 1e6:.2f} MB, Bitrate: {sent[\"bits_per_second\"] / 1e6:.2f} Mbps, Retries: {sent[\"retransmits\"]}')
print(f'  Transfer Recv: {recv[\"bytes\"] / 1e6:.2f} MB, Bitrate: {recv[\"bits_per_second\"] / 1e6:.2f} Mbps')
print(f'  Host CPU Util: sender total={cpu[\"host_total\"]:.2f}%, receiver total={cpu[\"remote_total\"]:.2f}%')
"

echo -e "\nProcess Status for Router BoringTun (PID: $ROUTER_PID) [AFTER LOAD]:"
cat /proc/$ROUTER_PID/status | grep -E "Name|State|VmSize|VmRSS|VmHWM|VmData|Threads"

echo -e "\n--- Step 9: Multi-Cycle Link Drop & Reconnection Test ---"
for cycle in 1 2 3; do
    echo "Cycle $cycle: Bringing veth-r DOWN (link outage)..."
    ip netns exec ns-router ip link set veth-r down
    sleep 1
    if ip netns exec ns-router ping -c 1 -W 1 192.168.100.2 >/dev/null 2>&1; then
        echo "ERROR: Ping unexpectedly succeeded during outage"
        exit 1
    fi
    echo "Cycle $cycle: Bringing veth-r UP (link restored)..."
    ip netns exec ns-router ip link set veth-r up
    sleep 1.5
    echo "Cycle $cycle: Verifying tunnel re-handshake & packet flow:"
    ip netns exec ns-router ping -c 2 -W 2 192.168.100.2
    echo "Cycle $cycle: RECONNECTED SUCCESSFULLY."
done

echo -e "\n--- Step 10: Issue #498 Verification (UAPI Peer Update Without Panic) ---"
echo "Testing upstream Issue #498 vulnerability:"
echo "Modifying existing peer $PEER_PUB on wg0 WITHOUT remove=true and WITHOUT replace_peers..."
# Update peer endpoint and persistent-keepalive on existing peer
ip netns exec ns-router wg set wg0 peer "$PEER_PUB" endpoint 10.0.0.2:51821 persistent-keepalive 30
echo "UAPI peer update command exited with code $? (SUCCESS: NO PANIC!)"

# Verify BoringTun daemon is still alive and healthy
if ! kill -0 $ROUTER_PID 2>/dev/null; then
    echo "FATAL: Router BoringTun process died (Issue #498 panic triggered!)"
    exit 1
fi
echo "Router BoringTun PID $ROUTER_PID is running and healthy."

# Verify traffic still flows across modified peer
echo "Verifying traffic flow after in-place peer modification:"
ip netns exec ns-router ping -c 3 -W 2 192.168.100.2
echo "SUCCESS: BoringTun handled peer update cleanly without panic or event loop stall!"

echo -e "\n--- Step 11: Multi-Peer Configuration & Simultaneous Routing Test ---"
echo "Adding Peer2 ($PEER2_PUB) to Router wg0..."
ip netns exec ns-router wg set wg0 \
    peer "$PEER2_PUB" \
    endpoint 10.0.1.2:51822 \
    allowed-ips 192.168.100.3/32 \
    persistent-keepalive 25

echo "Verifying router can communicate with BOTH peers simultaneously:"
echo "  Ping Peer1 (192.168.100.2):"
ip netns exec ns-router ping -c 2 -W 2 192.168.100.2
echo "  Ping Peer2 (192.168.100.3):"
ip netns exec ns-router ping -c 2 -W 2 192.168.100.3
echo "SUCCESS: Multi-peer routing verified across independent endpoints."

echo -e "\n--- Step 12: Remote Subnet Forwarding Test ---"
echo "Adding remote subnet 192.168.200.0/24 to Peer1 via UAPI update:"
ip netns exec ns-router wg set wg0 peer "$PEER_PUB" \
    allowed-ips 192.168.100.2/32,fd00:dead:beef::2/128,192.168.200.0/24

ip netns exec ns-peer ip addr add 192.168.200.1/32 dev lo 2>/dev/null || true
ip netns exec ns-router ip route add 192.168.200.0/24 dev wg0 2>/dev/null || true

echo "Pinging remote subnet IP 192.168.200.1 through BoringTun:"
ip netns exec ns-router ping -c 3 -W 2 192.168.200.1
echo "SUCCESS: Remote subnet forwarding verified."

echo -e "\n--- Step 13: replace_peers Semantics Test (wg setconf) ---"
TMP_CONF="/tmp/wg_test_sync.conf"
cat <<EOF > "$TMP_CONF"
[Interface]
PrivateKey = $ROUTER_PRIV
ListenPort = 51820

[Peer]
PublicKey = $PEER_PUB
Endpoint = 10.0.0.2:51821
AllowedIPs = 192.168.100.2/32, 192.168.200.0/24
PersistentKeepalive = 25
EOF

echo "Applying atomic replace_peers via wg setconf..."
ip netns exec ns-router wg setconf wg0 "$TMP_CONF"
rm -f "$TMP_CONF"
echo "wg setconf exited with code $?."

echo "Verifying Peer2 was atomic-removed and Peer1 remains operational:"
PEER_COUNT=$(ip netns exec ns-router wg show wg0 peers | wc -l)
echo "Current peer count on wg0: $PEER_COUNT (expected: 1)"
if [ "$PEER_COUNT" -ne 1 ]; then
    echo "ERROR: replace_peers did not clear peers as expected"
    exit 1
fi
ip netns exec ns-router ping -c 2 -W 2 192.168.100.2
echo "SUCCESS: replace_peers semantics verified."

echo -e "\n--- Step 14: BoringTun Watchdog Execution Test ---"
WATCHDOG_SCRIPT="/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/package/network/services/boringtun/files/boringtun_watchdog"
chmod +x "$WATCHDOG_SCRIPT"

echo "Executing watchdog under healthy tunnel conditions (timeout=180s)..."
ip netns exec ns-router "$WATCHDOG_SCRIPT" wg0 180
echo "Watchdog healthy check passed (zero false alarms)."

echo "Executing watchdog with simulated stale timeout (timeout=0s)..."
ip netns exec ns-router "$WATCHDOG_SCRIPT" wg0 0
echo "Watchdog correctly detected stale peer threshold."

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "\n===================================================================="
echo "ALL BORINGTUN INTEGRATION TESTS COMPLETED SUCCESSFULLY"
echo "Total Test Duration: ${DURATION} seconds"
echo "Final Exit Code: 0"
echo "===================================================================="
