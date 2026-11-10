#!/bin/bash
set -eo pipefail

echo "===================================================================="
echo "BoringTun 0.7.1 Linux Network Namespace Integration Test Suite"
echo "Target: CR8818 Firmware Architecture Validation"
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
    pkill -9 -f "iperf3.*-s" 2>/dev/null || true
    ip netns del ns-router 2>/dev/null || true
    ip netns del ns-peer 2>/dev/null || true
    rm -rf /tmp/bt_test_* /tmp/router_priv /tmp/peer_priv /var/run/wireguard/wg0.sock /var/run/wireguard/wg1.sock 2>/dev/null || true
    echo "[CLEANUP] Complete."
}
trap cleanup EXIT

cleanup 2>/dev/null || true

echo -e "\n--- Step 1: Setting up network namespaces and veth interconnect ---"
ip netns add ns-router
ip netns add ns-peer

ip link add veth-r type veth peer name veth-p
ip link set veth-r netns ns-router
ip link set veth-p netns ns-peer

ip netns exec ns-router ip link set lo up
ip netns exec ns-router ip addr add 10.0.0.1/24 dev veth-r
ip netns exec ns-router ip link set veth-r up

ip netns exec ns-peer ip link set lo up
ip netns exec ns-peer ip addr add 10.0.0.2/24 dev veth-p
ip netns exec ns-peer ip link set veth-p up

echo "Checking underlay connectivity between namespaces:"
ip netns exec ns-router ping -c 2 10.0.0.2

echo -e "\n--- Step 2: Generating WireGuard Keypairs ---"
ROUTER_PRIV=$(wg genkey)
ROUTER_PUB=$(echo "$ROUTER_PRIV" | wg pubkey)
PEER_PRIV=$(wg genkey)
PEER_PUB=$(echo "$PEER_PRIV" | wg pubkey)

echo "Router PubKey: $ROUTER_PUB"
echo "Peer PubKey:   $PEER_PUB"

mkdir -p /var/run/wireguard

echo -e "\n--- Step 3: Launching BoringTun Instances in Namespaces ---"
# Start router boringtun in ns-router
ip netns exec ns-router "$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug --disable-drop-privileges wg0 > /tmp/bt_router.log 2>&1 &
ROUTER_PID=$!

# Start peer boringtun in ns-peer
ip netns exec ns-peer "$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug --disable-drop-privileges wg1 > /tmp/bt_peer.log 2>&1 &
PEER_PID=$!

echo "Router BoringTun PID: $ROUTER_PID"
echo "Peer BoringTun PID:   $PEER_PID"

# Wait for TUN interfaces to appear
ready=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ip netns exec ns-router ip link show wg0 >/dev/null 2>&1 && ip netns exec ns-peer ip link show wg1 >/dev/null 2>&1; then
        echo "Both TUN interfaces (wg0, wg1) ready after $i attempts."
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
# Configure router wg0
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

# Configure peer wg1
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

echo -e "\n--- Step 5: Testing Initial Handshake & Bi-directional IPv4/IPv6 Ping ---"
echo "Pinging Peer from Router (IPv4):"
ip netns exec ns-router ping -c 3 192.168.100.2

echo "Pinging Router from Peer (IPv4):"
ip netns exec ns-peer ping -c 3 192.168.100.1

echo "Pinging Peer from Router (IPv6):"
ip netns exec ns-router ping -6 -c 3 fd00:dead:beef::2

echo -e "\nChecking WireGuard connection status on Router:"
ip netns exec ns-router wg show wg0

echo -e "\nChecking WireGuard connection status on Peer:"
ip netns exec ns-peer wg show wg1

echo -e "\n--- Step 6: Testing Issue #495 Regression (One-way deaf after 15-30s) ---"
echo "Sleeping 20 seconds to allow keepalive timers and session rotation triggers..."
sleep 20

echo "Testing Router -> Peer transmission after 20s idle:"
ip netns exec ns-router ping -c 3 -W 2 192.168.100.2

echo "Testing Peer -> Router transmission after 20s idle:"
ip netns exec ns-peer ping -c 3 -W 2 192.168.100.1

echo "Sleeping additional 15 seconds (total 35s since handshake)..."
sleep 15

echo "Testing Router -> Peer transmission after 35s total:"
ip netns exec ns-router ping -c 3 -W 2 192.168.100.2

echo "Testing Peer -> Router transmission after 35s total:"
ip netns exec ns-peer ping -c 3 -W 2 192.168.100.1

echo "SUCCESS: Issue #495 (one-way deaf) did NOT occur in boringtun-cli."

echo -e "\n--- Step 7: Measuring Real Memory Consumption (Idle & Under Load) ---"
echo "Process Memory Status for Router BoringTun (PID: $ROUTER_PID):"
grep -E "VmSize|VmRSS|VmHWM|VmData|Threads" /proc/$ROUTER_PID/status

echo -e "\n--- Step 8: Sustained Bi-Directional Throughput Test (iperf3) ---"
ip netns exec ns-peer iperf3 -s -D
sleep 1

echo "Running 10-second TCP throughput test through BoringTun tunnel:"
ip netns exec ns-router iperf3 -c 192.168.100.2 -t 10 -i 2

echo -e "\nProcess Memory Status for Router BoringTun AFTER iperf3 load:"
grep -E "VmSize|VmRSS|VmHWM|VmData|Threads" /proc/$ROUTER_PID/status

echo -e "\n--- Step 9: Tunnel Recovery & Reconnection Test ---"
echo "Simulating link drop: Bringing veth-r DOWN..."
ip netns exec ns-router ip link set veth-r down
sleep 2

echo "Verifying packets fail during outage:"
if ip netns exec ns-router ping -c 2 -W 1 192.168.100.2 >/dev/null 2>&1; then
    echo "ERROR: Ping unexpectedly succeeded during outage"
    exit 1
else
    echo "Confirmed: Packets dropped during link outage."
fi

echo "Restoring link: Bringing veth-r UP..."
ip netns exec ns-router ip link set veth-r up
sleep 2

echo "Verifying tunnel automatically re-establishes and resumes traffic:"
ip netns exec ns-router ping -c 4 -W 2 192.168.100.2
echo "SUCCESS: Tunnel successfully recovered after link failure!"

echo -e "\n--- Step 10: Final WireGuard Transfer Statistics ---"
ip netns exec ns-router wg show wg0
ip netns exec ns-peer wg show wg1

echo -e "\n===================================================================="
echo "ALL BORINGTUN INTEGRATION TESTS COMPLETED SUCCESSFULLY"
echo "===================================================================="
