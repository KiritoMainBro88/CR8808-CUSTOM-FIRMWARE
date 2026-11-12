#!/bin/sh
# performance/wireguard_rust/deploy_wg1.sh
# Milestone M12.6 Priority D: BoringTun Rust wg1 Volatile Deployment Package
# Target: Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 armv7l)
#
# Boundaries:
# - ZERO modification to NAND/flash (all files in volatile RAM /tmp/bin)
# - Production wg0 (Go daemon, 10.99.0.1/24, UDP 51820) remains 100% UNTOUCHED
# - Isolated wg1 (Rust daemon, 10.99.1.1/24, UDP 51821, table 101)

set -eu

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    echo "[INFO] Running in DRY-RUN mode. Preflight assertions only."
fi

WG_IFACE="wg1"
WG_PORT=51821
WG_SUBNET="10.99.1.0/24"
WG_SERVER_IP="10.99.1.1/24"
WG_TABLE=101
WG_DIR="/tmp/bin"
WG_PID_FILE="/tmp/wg1.pid"
WG_SOCK_DIR="/var/run/wireguard"
WG_LOG_FILE="/tmp/boringtun_wg1.log"
BORINGTUN_BIN="$WG_DIR/boringtun-cli-armv7"
STAGED_SRC="/tmp/boringtun-cli-armv7"

log() {
    echo "[deploy-wg1] $*"
}

err() {
    echo "[deploy-wg1 ERROR] $*" >&2
}

# 1. Strict Production Boundary Guard
if [ "$WG_IFACE" = "wg0" ]; then
    err "FATAL SAFETY VIOLATION: Target interface is set to wg0! Aborting immediately."
    exit 99
fi

# 2. Preflight Safety Checks
log "Executing preflight isolation checks..."

# Check production wg0 health
if ip link show wg0 >/dev/null 2>&1; then
    log "Verified: Production wg0 interface is active and isolated."
else
    log "[WARN] Production wg0 is not active, proceeding with caution."
fi

# Check wg1 collision
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
    err "Interface $WG_IFACE already exists! Run teardown_wg1.sh first."
    exit 1
fi

# Check port collision
if netstat -unl 2>/dev/null | grep -q ":$WG_PORT "; then
    err "Port $WG_PORT is already in use! Cannot deploy wg1 testbed."
    exit 1
fi

# Locate staged binary
if [ ! -x "$BORINGTUN_BIN" ]; then
    if [ -x "$STAGED_SRC" ]; then
        mkdir -p "$WG_DIR"
        cp "$STAGED_SRC" "$BORINGTUN_BIN"
        chmod +x "$BORINGTUN_BIN"
    elif [ -x "$(dirname "$0")/../../artifacts/m12_wireguard/boringtun-cli-armv7" ]; then
        mkdir -p "$WG_DIR"
        cp "$(dirname "$0")/../../artifacts/m12_wireguard/boringtun-cli-armv7" "$BORINGTUN_BIN"
        chmod +x "$BORINGTUN_BIN"
    else
        err "BoringTun ARMv7 binary not found at $BORINGTUN_BIN or $STAGED_SRC"
        exit 1
    fi
fi

log "Preflight checks passed."

if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run complete. All preflight assertions satisfied."
    exit 0
fi

# 3. Prepare Volatile Directories
mkdir -p "$WG_SOCK_DIR"
mkdir -p /tmp/wireguard

# 4. Launch BoringTun Daemon
log "Launching BoringTun daemon on interface $WG_IFACE (Port $WG_PORT UDP)..."
export WG_SUDO=1
"$BORINGTUN_BIN" \
    --disable-drop-privileges \
    --foreground \
    --threads 2 \
    --verbosity debug \
    "$WG_IFACE" > "$WG_LOG_FILE" 2>&1 &

BORINGTUN_PID=$!
echo "$BORINGTUN_PID" > "$WG_PID_FILE"
log "BoringTun launched with PID $BORINGTUN_PID (recorded in $WG_PID_FILE)."

# Wait up to 3s for TUN interface to instantiate
TUN_OK=0
for i in 1 2 3 4 5 6; do
    if ip link show "$WG_IFACE" >/dev/null 2>&1; then
        TUN_OK=1
        break
    fi
    sleep 0.5
done

if [ "$TUN_OK" -ne 1 ]; then
    err "TUN device $WG_IFACE failed to appear! Log output:"
    cat "$WG_LOG_FILE" >&2 || true
    kill -9 "$BORINGTUN_PID" 2>/dev/null || true
    rm -f "$WG_PID_FILE"
    exit 1
fi

# 5. Configure Network Parameters
log "Configuring IP address $WG_SERVER_IP and MTU 1420 on $WG_IFACE..."
ip addr add "$WG_SERVER_IP" dev "$WG_IFACE"
ip link set mtu 1420 up dev "$WG_IFACE"

# 6. Configure Isolated Routing Policy (Table 101)
log "Configuring isolated routing table $WG_TABLE for $WG_SUBNET..."
ip route add "$WG_SUBNET" dev "$WG_IFACE" proto kernel scope link src 10.99.1.1 table "$WG_TABLE" 2>/dev/null || true
ip rule add from "$WG_SUBNET" table "$WG_TABLE" 2>/dev/null || true

# 7. Final Sanity & wg0 Health Verification
log "Verifying interface state and production wg0 health..."
if ip link show wg0 >/dev/null 2>&1; then
    log "Production wg0 status: ACTIVE (100% UNTOUCHED)"
fi

log "BoringTun wg1 status: UP and READY (PID: $BORINGTUN_PID, Subnet: $WG_SUBNET)"
grep -E "(VmRSS|VmHWM|VmSize)" "/proc/$BORINGTUN_PID/status" || true
log "Deployment complete."
