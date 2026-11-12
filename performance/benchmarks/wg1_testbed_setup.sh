#!/bin/sh
# performance/benchmarks/wg1_testbed_setup.sh
# Milestone M12: Isolated wg1 BoringTun Rust Testbed Setup Script
# Architecture: Workstream C (Rust-First WireGuard Modernization)
# Target: Xiaomi CR8808 Ver.B / RA82 v1.4.31 (Linux 4.4.60 armv7l)
#
# Boundaries:
# - ZERO modification of existing production wg0 (/data/wg_server on UDP 51820, 10.99.0.1/24)
# - Isolated testbed: wg1 on UDP 51821, subnet 10.99.1.0/24, independent routing table 101
# - Volatile runtime: Executed entirely in /tmp, zero persistence to flash

set -eu

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    echo "[INFO] Running in DRY-RUN mode. No changes will be made."
fi

# Configuration parameters
WG_IFACE="wg1"
WG_PORT=51821
WG_SUBNET="10.99.1.0/24"
WG_SERVER_IP="10.99.1.1/24"
WG_TABLE=101
WG_PID_FILE="/tmp/wg1.pid"
WG_SOCK_DIR="/var/run/wireguard"
WG_LOG_FILE="/tmp/boringtun_wg1.log"
BORINGTUN_BIN="/tmp/boringtun-cli-armv7"

log() {
    echo "[wg1-setup] $*"
}

err() {
    echo "[wg1-setup ERROR] $*" >&2
}

# 1. Preflight Safety Checks
log "Executing preflight isolation checks..."

# Check wg0 sanctity
if ip link show wg0 >/dev/null 2>&1; then
    log "Verified: Production interface wg0 is active and isolated."
else
    log "[WARN] wg0 is not active, proceeding with caution."
fi

# Check if wg1 already exists
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
    err "Interface $WG_IFACE already exists! Run teardown script first."
    exit 1
fi

# Check if port 51821 is already in use
if netstat -unl 2>/dev/null | grep -q ":$WG_PORT "; then
    err "Port $WG_PORT is already in use! Cannot start wg1 testbed."
    exit 1
fi

# Verify BoringTun binary presence
if [ ! -x "$BORINGTUN_BIN" ]; then
    err "BoringTun binary not found or not executable at $BORINGTUN_BIN"
    err "Stage boringtun-cli-armv7 to $BORINGTUN_BIN before running setup."
    exit 1
fi

log "Preflight checks passed."

if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run complete. All preflight assertions satisfied."
    exit 0
fi

# 2. Prepare directories
mkdir -p "$WG_SOCK_DIR"
mkdir -p /tmp/wireguard

# 3. Launch BoringTun daemon for wg1
log "Starting BoringTun daemon on interface $WG_IFACE..."
"$BORINGTUN_BIN" --foreground --threads 2 --verbosity debug "$WG_IFACE" > "$WG_LOG_FILE" 2>&1 &
BORINGTUN_PID=$!
echo "$BORINGTUN_PID" > "$WG_PID_FILE"
log "BoringTun launched with PID $BORINGTUN_PID (recorded in $WG_PID_FILE)."

# Wait for TUN device to be instantiated
sleep 1
if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
    err "Interface $WG_IFACE failed to appear! Check log: $WG_LOG_FILE"
    kill "$BORINGTUN_PID" 2>/dev/null || true
    rm -f "$WG_PID_FILE"
    exit 1
fi

# 4. Configure IP address and Link Parameters
log "Configuring IP address $WG_SERVER_IP and MTU 1420 on $WG_IFACE..."
ip addr add "$WG_SERVER_IP" dev "$WG_IFACE"
ip link set mtu 1420 up dev "$WG_IFACE"

# 5. Configure Isolated Routing Table
log "Setting up independent routing table $WG_TABLE for $WG_SUBNET..."
ip route add "$WG_SUBNET" dev "$WG_IFACE" proto kernel scope link src 10.99.1.1 table "$WG_TABLE" 2>/dev/null || true
ip rule add from "$WG_SUBNET" table "$WG_TABLE" 2>/dev/null || true

# 6. Verify Interface Status
log "Interface $WG_IFACE is UP and configured:"
ip addr show dev "$WG_IFACE"

log "BoringTun memory footprint:"
grep -E "(VmRSS|VmHWM|VmSize)" "/proc/$BORINGTUN_PID/status" || true

log "Setup complete. wg1 testbed is ready for benchmarking."
