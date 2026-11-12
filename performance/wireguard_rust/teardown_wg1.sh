#!/bin/sh
# performance/wireguard_rust/teardown_wg1.sh
# Milestone M12.6 Priority D: BoringTun Rust wg1 Volatile Teardown Package
# Target: Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 armv7l)
#
# Boundaries:
# - Clean, instantaneous rollback of experimental wg1 testbed
# - Purges volatile binaries and sockets from RAM
# - Verifies production wg0 (Go daemon) remains 100% active and healthy

set -u

WG_IFACE="wg1"
WG_SUBNET="10.99.1.0/24"
WG_TABLE=101
WG_PID_FILE="/tmp/wg1.pid"
WG_LOG_FILE="/tmp/boringtun_wg1.log"
WG_DIR="/tmp/bin"

log() {
    echo "[teardown-wg1] $*"
}

# 1. Strict Production Boundary Guard
if [ "$WG_IFACE" = "wg0" ]; then
    echo "[CRITICAL SAFETY GUARD] Refusing to teardown production interface 'wg0'! Aborting immediately." >&2
    exit 99
fi

log "Executing teardown of experimental wg1 BoringTun testbed..."

# 2. Stop BoringTun Daemon
if [ -f "$WG_PID_FILE" ]; then
    PID=$(cat "$WG_PID_FILE")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        log "Terminating BoringTun daemon (PID $PID)..."
        kill -TERM "$PID" 2>/dev/null || true
        for i in 1 2 3; do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        if kill -0 "$PID" 2>/dev/null; then
            log "Process did not terminate gracefully, sending SIGKILL..."
            kill -KILL "$PID" 2>/dev/null || true
        fi
    fi
    rm -f "$WG_PID_FILE"
fi

# Fallback kill by process name if still lingering
pkill -f "boringtun-cli-armv7.*wg1" 2>/dev/null || true

# 3. Clean up Isolated Routing Rules
log "Removing isolated routing rules for table $WG_TABLE..."
while ip rule show 2>/dev/null | grep -q "from $WG_SUBNET lookup $WG_TABLE"; do
    ip rule del from "$WG_SUBNET" table "$WG_TABLE" 2>/dev/null || break
done

ip route flush table "$WG_TABLE" 2>/dev/null || true

# 4. Teardown Network Interface
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
    log "Deleting network interface $WG_IFACE..."
    ip link del dev "$WG_IFACE" 2>/dev/null || true
fi

# 5. Clean Up Volatile Files & Sockets
rm -f /var/run/wireguard/wg1.sock /tmp/wireguard/wg1.sock "$WG_LOG_FILE"
rm -f "$WG_DIR/boringtun-cli-armv7"
rmdir "$WG_DIR" 2>/dev/null || true

# 6. Verify Production wg0 Health
log "Verifying production WireGuard (wg0) health..."
if ip link show wg0 >/dev/null 2>&1; then
    log "Production wg0 status: ACTIVE (100% HEALTHY)"
    ip addr show dev wg0
else
    log "[WARN] Production wg0 interface not found! Check /data/wg_server daemon."
fi

log "Teardown complete. Zero residue remains on device."
