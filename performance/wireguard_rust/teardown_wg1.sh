#!/bin/sh
# performance/wireguard_rust/teardown_wg1.sh
# Milestone M12.6 Priority D: Owned-Only Volatile Teardown Package
#
# Boundaries:
# - Requires exact owned-resource manifest written by deploy_wg1.sh (zero pkill -f or blanket table flush)
# - Refuses any operation targeting wg0 (exit 99)
# - Verifies PID command line before sending signals; aborts & preserves state if owned daemon won't stop
# - Verifies production wg0 pre vs post invariance

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wg1_common.sh
. "${SCRIPT_DIR}/wg1_common.sh"

WG_IFACE="${WG_IFACE:-wg1}"
WG_TABLE="${WG_TABLE:-101}"
WG_MANIFEST="${WG_MANIFEST:-/tmp/wg1_owned_manifest.env}"
PROC_ROOT="${PROC_ROOT:-/proc}"

log() {
    echo "[teardown-wg1] $*"
}

err() {
    echo "[teardown-wg1 ERROR] $*" >&2
}

# 1. Strict Production Boundary Guard
if [ "$WG_IFACE" = "wg0" ]; then
    err "CRITICAL SAFETY GUARD: Refusing to teardown production interface 'wg0'! Aborting immediately."
    exit 99
fi

if [ ! -f "$WG_MANIFEST" ]; then
    err "Owned resource manifest not found at $WG_MANIFEST. Refusing blind pkill / ip route flush cleanup."
    exit 1
fi

OWNED_IFACE=$(wg1_manifest_get "OWNED_IFACE" "$WG_MANIFEST" || echo "")
OWNED_PORT=$(wg1_manifest_get "OWNED_PORT" "$WG_MANIFEST" || echo "")
OWNED_SUBNET=$(wg1_manifest_get "OWNED_SUBNET" "$WG_MANIFEST" || echo "")
OWNED_SERVER_IP=$(wg1_manifest_get "OWNED_SERVER_IP" "$WG_MANIFEST" || echo "")
OWNED_TABLE=$(wg1_manifest_get "OWNED_TABLE" "$WG_MANIFEST" || echo "")
OWNED_PID=$(wg1_manifest_get "OWNED_PID" "$WG_MANIFEST" || echo "")
OWNED_PID_FILE=$(wg1_manifest_get "OWNED_PID_FILE" "$WG_MANIFEST" || echo "")
OWNED_LOG_FILE=$(wg1_manifest_get "OWNED_LOG_FILE" "$WG_MANIFEST" || echo "")
OWNED_WG_DIR=$(wg1_manifest_get "OWNED_WG_DIR" "$WG_MANIFEST" || echo "")
OWNED_WG_DIR_CREATED=$(wg1_manifest_get "OWNED_WG_DIR_CREATED" "$WG_MANIFEST" || echo "0")
OWNED_BIN_PATH=$(wg1_manifest_get "OWNED_BIN_PATH" "$WG_MANIFEST" || echo "")
OWNED_BIN_CREATED=$(wg1_manifest_get "OWNED_BIN_CREATED" "$WG_MANIFEST" || echo "0")
OWNED_SOCK_DIR=$(wg1_manifest_get "OWNED_SOCK_DIR" "$WG_MANIFEST" || echo "")
OWNED_SOCK_DIR_CREATED=$(wg1_manifest_get "OWNED_SOCK_DIR_CREATED" "$WG_MANIFEST" || echo "0")
OWNED_SOCK_PRIMARY=$(wg1_manifest_get "OWNED_SOCK_PRIMARY" "$WG_MANIFEST" || echo "")
OWNED_SOCK_TMP=$(wg1_manifest_get "OWNED_SOCK_TMP" "$WG_MANIFEST" || echo "")
OWNED_TMP_DIR=$(wg1_manifest_get "OWNED_TMP_DIR" "$WG_MANIFEST" || echo "")
OWNED_TMP_DIR_CREATED=$(wg1_manifest_get "OWNED_TMP_DIR_CREATED" "$WG_MANIFEST" || echo "0")
OWNED_ROUTE_CREATED=$(wg1_manifest_get "OWNED_ROUTE_CREATED" "$WG_MANIFEST" || echo "0")
OWNED_RULE_CREATED=$(wg1_manifest_get "OWNED_RULE_CREATED" "$WG_MANIFEST" || echo "0")

wg1_guard_production "$OWNED_IFACE" "${OWNED_PORT:-51821}" "${OWNED_SUBNET:-10.99.1.0/24}" "${OWNED_SERVER_IP:-10.99.1.1/24}"

WG0_PRE_SNAPSHOT=$(wg1_capture_wg0_fingerprint "${OWNED_TABLE:-$WG_TABLE}" "$PROC_ROOT")
log "Executing owned-resource teardown of $OWNED_IFACE (manifest: $WG_MANIFEST)..."

# 2. Stop ONLY exact owned PID (never pkill -f)
if [ -n "$OWNED_PID" ]; then
    log "Stopping owned daemon PID $OWNED_PID (cmdline verified)..."
    if ! wg1_stop_owned_pid "$OWNED_PID" "$OWNED_IFACE" "$PROC_ROOT"; then
        err "CRITICAL: Owned daemon PID $OWNED_PID could not be terminated! Aborting teardown and preserving manifest."
        exit 1
    fi
fi

# 3. Remove ONLY owned policy rule and exact owned route (never ip route flush table)
if [ "$OWNED_RULE_CREATED" = "1" ] && [ -n "$OWNED_SUBNET" ] && [ -n "$OWNED_TABLE" ]; then
    if ip rule show 2>/dev/null | grep -q "from ${OWNED_SUBNET} lookup ${OWNED_TABLE}"; then
        log "Deleting owned rule: from $OWNED_SUBNET table $OWNED_TABLE..."
        ip rule del from "$OWNED_SUBNET" table "$OWNED_TABLE"
    fi
fi

if [ "$OWNED_ROUTE_CREATED" = "1" ] && [ -n "$OWNED_SUBNET" ] && [ -n "$OWNED_TABLE" ]; then
    if ip route show table "$OWNED_TABLE" 2>/dev/null | grep -qE "^${OWNED_SUBNET}.*dev ${OWNED_IFACE}"; then
        log "Deleting owned route: $OWNED_SUBNET dev $OWNED_IFACE table $OWNED_TABLE..."
        ip route del "$OWNED_SUBNET" dev "$OWNED_IFACE" table "$OWNED_TABLE"
    fi
fi

# 4. Teardown ONLY owned interface
if [ -n "$OWNED_IFACE" ] && ip link show "$OWNED_IFACE" >/dev/null 2>&1; then
    log "Deleting network interface $OWNED_IFACE..."
    ip link del dev "$OWNED_IFACE"
fi

# 5. Remove ONLY files and directories owned by this deployment
[ -n "$OWNED_SOCK_PRIMARY" ] && rm -f "$OWNED_SOCK_PRIMARY"
[ -n "$OWNED_SOCK_TMP" ] && rm -f "$OWNED_SOCK_TMP"
[ -n "$OWNED_PID_FILE" ] && rm -f "$OWNED_PID_FILE"
[ -n "$OWNED_LOG_FILE" ] && rm -f "$OWNED_LOG_FILE"

if [ "$OWNED_BIN_CREATED" = "1" ] && [ -n "$OWNED_BIN_PATH" ]; then
    rm -f "$OWNED_BIN_PATH"
fi

if [ "$OWNED_WG_DIR_CREATED" = "1" ] && [ -n "$OWNED_WG_DIR" ]; then
    rmdir "$OWNED_WG_DIR" 2>/dev/null || true
fi
if [ "$OWNED_TMP_DIR_CREATED" = "1" ] && [ -n "$OWNED_TMP_DIR" ]; then
    rmdir "$OWNED_TMP_DIR" 2>/dev/null || true
fi
if [ "$OWNED_SOCK_DIR_CREATED" = "1" ] && [ -n "$OWNED_SOCK_DIR" ]; then
    rmdir "$OWNED_SOCK_DIR" 2>/dev/null || true
fi

rm -f "$WG_MANIFEST"

# 6. Verify Production wg0 Pre/Post Invariance
WG0_POST_SNAPSHOT=$(wg1_capture_wg0_fingerprint "${OWNED_TABLE:-$WG_TABLE}" "$PROC_ROOT")
if [ "$WG0_PRE_SNAPSHOT" != "$WG0_POST_SNAPSHOT" ]; then
    err "CRITICAL: Production wg0 state or unrelated policy rules changed during teardown!"
    exit 1
fi

if ip link show wg0 >/dev/null 2>&1; then
    log "Production wg0 status: ACTIVE (100% INVARIANT)"
else
    log "Pre/post wg0 invariance check passed."
fi

log "Owned-resource teardown complete."
