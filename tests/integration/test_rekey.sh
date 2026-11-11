#!/bin/bash
set -eo pipefail

BORINGTUN_BIN="/root/work/boringtun-boringtun-cli-0.7.1/target/release/boringtun-cli"

cleanup() {
    kill $(jobs -p) 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wg_rk" 2>/dev/null || true
    ip netns del ns-rk-router 2>/dev/null || true
    ip netns del ns-rk-peer 2>/dev/null || true
    rm -f /var/run/wireguard/wg_rk*.sock /tmp/rk_*
}
trap cleanup EXIT
cleanup 2>/dev/null || true

ip netns add ns-rk-router
ip netns add ns-rk-peer

# veth interconnect
ip link add veth-r type veth peer name veth-p
ip link set veth-r netns ns-rk-router
ip link set veth-p netns ns-rk-peer

ip netns exec ns-rk-router ip addr add 10.10.0.1/24 dev veth-r
ip netns exec ns-rk-router ip link set veth-r up
ip netns exec ns-rk-peer ip addr add 10.10.0.2/24 dev veth-p
ip netns exec ns-rk-peer ip link set veth-p up

# Start BoringTun
ip netns exec ns-rk-router "$BORINGTUN_BIN" --foreground --threads 1 --disable-drop-privileges wg_rk0 >/dev/null 2>&1 &
PID_R=$!
ip netns exec ns-rk-peer "$BORINGTUN_BIN" --foreground --threads 1 --disable-drop-privileges wg_rk1 >/dev/null 2>&1 &
PID_P=$!
sleep 0.5

R_PRIV=$(wg genkey)
R_PUB=$(echo "$R_PRIV" | wg pubkey)
P_PRIV=$(wg genkey)
P_PUB=$(echo "$P_PRIV" | wg pubkey)

echo "$R_PRIV" > /tmp/rk_r_priv
ip netns exec ns-rk-router wg set wg_rk0 private-key /tmp/rk_r_priv listen-port 51820 peer "$P_PUB" endpoint 10.10.0.2:51821 allowed-ips 192.168.150.2/32 persistent-keepalive 25
ip netns exec ns-rk-router ip addr add 192.168.150.1/24 dev wg_rk0
ip netns exec ns-rk-router ip link set wg_rk0 up

echo "$P_PRIV" > /tmp/rk_p_priv
ip netns exec ns-rk-peer wg set wg_rk1 private-key /tmp/rk_p_priv listen-port 51821 peer "$R_PUB" endpoint 10.10.0.1:51820 allowed-ips 192.168.150.1/32 persistent-keepalive 25
ip netns exec ns-rk-peer ip addr add 192.168.150.2/24 dev wg_rk1
ip netns exec ns-rk-peer ip link set wg_rk1 up

# Initial handshake
ip netns exec ns-rk-router ping -c 1 192.168.150.2 >/dev/null
INITIAL_HS=$(ip netns exec ns-rk-router wg show wg_rk0 latest-handshakes | awk '{print $2}')
echo "Initial handshake timestamp (relative seconds or epoch): $INITIAL_HS"

# In BoringTun, latest-handshake returns seconds since handshake
# We can monitor handshake over time while running continuous traffic
echo "Testing continuous bidirectional traffic across rekey threshold..."
# Send ping every 2 seconds for 130 seconds
LOSS=0
COUNT=0
REKEY_SEEN=0

for i in $(seq 1 65); do
    if ! ip netns exec ns-rk-router ping -c 1 -W 1 192.168.150.2 >/dev/null 2>&1; then
        echo "Packet lost at step $i!"
        LOSS=$((LOSS + 1))
    fi
    COUNT=$((COUNT + 1))
    CURRENT_HS=$(ip netns exec ns-rk-router wg show wg_rk0 latest-handshakes | awk '{print $2}')
    # If CURRENT_HS is relative seconds, when rekey happens, CURRENT_HS drops back to 0 or 1!
    # Because BoringTun reports elapsed seconds since last handshake!
    if [ "$i" -gt 55 ] && [ "$CURRENT_HS" -lt 15 ]; then
        echo "REKEY DETECTED at step $i (elapsed ~$(($i * 2))s): latest-handshake reset to $CURRENT_HS s"
        REKEY_SEEN=1
        break
    fi
    sleep 2
done

echo "Rekey test finished. Total pings: $COUNT, Losses: $LOSS, Rekey observed: $REKEY_SEEN"
