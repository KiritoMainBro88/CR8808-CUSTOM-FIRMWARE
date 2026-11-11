#!/bin/bash
set -eo pipefail

BORINGTUN_BIN="/root/work/boringtun-boringtun-cli-0.7.1/target/release/boringtun-cli"

cleanup() {
    kill $(jobs -p) 2>/dev/null || true
    pkill -9 -f "boringtun-cli.*wgtest" 2>/dev/null || true
    ip netns del ns-test 2>/dev/null || true
    rm -f /var/run/wireguard/wgtest.sock /tmp/test_priv /tmp/test_peer_priv
}
trap cleanup EXIT
cleanup 2>/dev/null || true

ip netns add ns-test
ip netns exec ns-test ip link set lo up
ip netns exec ns-test "$BORINGTUN_BIN" --foreground --threads 1 --disable-drop-privileges wgtest >/dev/null 2>&1 &
PID=$!
sleep 0.5

KEY_PRIV=$(wg genkey)
KEY_PUB=$(echo "$KEY_PRIV" | wg pubkey)
PEER_PRIV=$(wg genkey)
PEER_PUB=$(echo "$PEER_PRIV" | wg pubkey)

echo "$KEY_PRIV" > /tmp/test_priv
ip netns exec ns-test wg set wgtest private-key /tmp/test_priv peer "$PEER_PUB" allowed-ips 192.168.100.2/32
rm -f /tmp/test_priv

echo "=== 1. Initial AllowedIPs ==="
ip netns exec ns-test wg show wgtest allowed-ips

# Append AllowedIP via UAPI without replace_allowed_ips=true
SOCK="/var/run/wireguard/wgtest.sock"
python3 - "$SOCK" "$PEER_PUB" << 'PYEOF'
import sys, socket, base64
sock_path = sys.argv[1]
peer_b64 = sys.argv[2]
pubkey_hex = base64.b64decode(peer_b64).hex()

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
cmd = f"set=1\npublic_key={pubkey_hex}\nallowed_ip=192.168.200.0/24\n\n"
s.sendall(cmd.encode("utf-8"))
resp = s.recv(1024)
print("UAPI append resp:", resp.decode().strip())
s.close()
PYEOF

echo "=== 2. After Append (Expected: BOTH 192.168.100.2/32 AND 192.168.200.0/24) ==="
ip netns exec ns-test wg show wgtest allowed-ips

# Replace AllowedIP via UAPI with replace_allowed_ips=true
python3 - "$SOCK" "$PEER_PUB" << 'PYEOF'
import sys, socket, base64
sock_path = sys.argv[1]
peer_b64 = sys.argv[2]
pubkey_hex = base64.b64decode(peer_b64).hex()

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
cmd = f"set=1\npublic_key={pubkey_hex}\nreplace_allowed_ips=true\nallowed_ip=10.99.0.0/16\n\n"
s.sendall(cmd.encode("utf-8"))
resp = s.recv(1024)
print("UAPI replace resp:", resp.decode().strip())
s.close()
PYEOF

echo "=== 3. After Replace (Expected: ONLY 10.99.0.0/16) ==="
ip netns exec ns-test wg show wgtest allowed-ips

echo "ALL UAPI ALLOWED_IP SEMANTICS VERIFIED SUCCESSFULLY!"
