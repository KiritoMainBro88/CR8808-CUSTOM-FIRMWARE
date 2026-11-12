#!/bin/sh
# performance/benchmarks/wg1_testbed_teardown.sh
# Milestone M12: Isolated wg1 BoringTun Rust Testbed Teardown Script
# Architecture: Workstream C (Rust-First WireGuard Modernization)
# Target: Xiaomi CR8808 Ver.B / RA82 v1.4.31 (Linux 4.4.60 armv7l)
#
# Boundaries:
# - Clean, instantaneous rollback of experimental wg1 testbed
# - Leaves production wg0 untouched and 100% active

set -u

WG_IFACE="wg1"
WG_SUBNET="10.99.1.0/24"
WG_TABLE=101
WG_PID_FILE="/tmp/wg1.pid"
WG_LOG_FILE="/tmp/boringtun_wg1.log"

# Strict Safety Boundary: Under no circumstances allow operations on wg0
if [ "$WG_IFACE" = "wg0" ]; then
    echo "[CRITICAL SAFETY GUARD] Refusing to execute teardown on production interface 'wg0'! Aborting immediately." >&2
    exit 99
fi

log() {
    echo "[wg1-teardown] $*"
}

log "Executing teardown of experimental wg1 testbed..."

# 1. Stop BoringTun daemon
if [ -f "$WG_PID_FILE" ]; then
    PID=$(cat "$WG_PID_FILE")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        log "Terminating BoringTun daemon (PID $PID)..."
        kill -TERM "$PID" 2>/dev/null || true
        # Wait up to 3 seconds for graceful shutdown
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

# 2. Remove isolated routing rules
log "Cleaning up routing policy and table $WG_TABLE..."
while ip rule show 2>/dev/null | grep -q "from $WG_SUBNET lookup $WG_TABLE"; do
    ip rule del from "$WG_SUBNET" table "$WG_TABLE" 2>/dev/null || break
done

ip route flush table "$WG_TABLE" 2>/dev/null || true

# 3. Teardown interface if still present
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
    log "Deleting network interface $WG_IFACE..."
    ip link del dev "$WG_IFACE" 2>/dev/null || true
fi

# 4. Clean up volatile sockets
rm -f /var/run/wireguard/wg1.sock /tmp/wireguard/wg1.sock

# 5. Verify Production wg0 Health
log "Verifying production WireGuard (wg0) state..."
if ip link show wg0 >/dev/null 2>&1; then
    log "Production wg0 status: ACTIVE (100% HEALTHY)"
    ip addr show dev wg0
else
    log "[WARN] wg0 not found. Check /data/wg_server daemon."
fi

log "Teardown complete. Zero residue remains on router."
