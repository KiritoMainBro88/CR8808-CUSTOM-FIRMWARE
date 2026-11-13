#!/bin/sh
# performance/wireguard_rust/deploy_wg1.sh
# Milestone M12.6 Priority D: BoringTun Rust wg1 Volatile Deployment Package
#
# Boundaries:
# - ZERO modification to NAND/flash (all volatile paths in RAM /tmp)
# - Production wg0 (Go daemon, 10.99.0.1/24, UDP 51820) verified untouched pre & post
# - Isolated wg1 (Rust daemon, 10.99.1.1/24, UDP 51821, table 101)
# - --dry-run performs ZERO filesystem or network mutations
# - Exact owned-resource manifest enables selective teardown & partial-failure rollback

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wg1_common.sh
. "${SCRIPT_DIR}/wg1_common.sh"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

WG_IFACE="${WG_IFACE:-wg1}"
WG_PORT="${WG_PORT:-51821}"
WG_SUBNET="${WG_SUBNET:-10.99.1.0/24}"
WG_SERVER_IP="${WG_SERVER_IP:-10.99.1.1/24}"
WG_SERVER_ADDR="${WG_SERVER_IP%/*}"
WG_TABLE="${WG_TABLE:-101}"
WG_DIR="${WG_DIR:-/tmp/bin}"
WG_TMP_DIR="${WG_TMP_DIR:-/tmp/wireguard}"
WG_PID_FILE="${WG_PID_FILE:-/tmp/wg1.pid}"
WG_SOCK_DIR="${WG_SOCK_DIR:-/var/run/wireguard}"
WG_LOG_FILE="${WG_LOG_FILE:-/tmp/boringtun_wg1.log}"
WG_MANIFEST="${WG_MANIFEST:-/tmp/wg1_owned_manifest.env}"
PROC_ROOT="${PROC_ROOT:-/proc}"
BORINGTUN_BIN="${BORINGTUN_BIN:-${WG_DIR}/boringtun-cli-armv7}"
STAGED_SRC="${STAGED_SRC:-/tmp/boringtun-cli-armv7}"
REPO_ARTIFACT_BIN="${SCRIPT_DIR}/../../artifacts/m12_wireguard/boringtun-cli-armv7"

log() {
    echo "[deploy-wg1] $*"
}

err() {
    echo "[deploy-wg1 ERROR] $*" >&2
}

# 1. Strict Production Boundary Guard
wg1_guard_production "$WG_IFACE" "$WG_PORT" "$WG_SUBNET" "$WG_SERVER_IP"

# Track only resources actually created by this invocation for atomic rollback
CREATED_WG_DIR=0
CREATED_BIN=0
CREATED_SOCK_DIR=0
CREATED_TMP_DIR=0
CREATED_PID_FILE=0
CREATED_LOG_FILE=0
OWNED_PID=""
CREATED_IFACE=0
ADDED_ROUTE=0
ADDED_RULE=0
ROLLBACK_ARMED=0

write_manifest() {
    _status="$1"
    mkdir -p "$(dirname "$WG_MANIFEST")"
    cat << EOF > "$WG_MANIFEST"
DEPLOY_STATUS=${_status}
OWNED_IFACE=${WG_IFACE}
OWNED_PORT=${WG_PORT}
OWNED_SUBNET=${WG_SUBNET}
OWNED_SERVER_IP=${WG_SERVER_IP}
OWNED_SERVER_ADDR=${WG_SERVER_ADDR}
OWNED_TABLE=${WG_TABLE}
OWNED_PID=${OWNED_PID}
OWNED_PID_FILE=${WG_PID_FILE}
OWNED_LOG_FILE=${WG_LOG_FILE}
OWNED_WG_DIR=${WG_DIR}
OWNED_WG_DIR_CREATED=${CREATED_WG_DIR}
OWNED_BIN_PATH=${BORINGTUN_BIN}
OWNED_BIN_CREATED=${CREATED_BIN}
OWNED_SOCK_DIR=${WG_SOCK_DIR}
OWNED_SOCK_DIR_CREATED=${CREATED_SOCK_DIR}
OWNED_SOCK_PRIMARY=${WG_SOCK_DIR}/${WG_IFACE}.sock
OWNED_SOCK_TMP=${WG_TMP_DIR}/${WG_IFACE}.sock
OWNED_TMP_DIR=${WG_TMP_DIR}
OWNED_TMP_DIR_CREATED=${CREATED_TMP_DIR}
OWNED_IFACE_CREATED=${CREATED_IFACE}
OWNED_ROUTE_CREATED=${ADDED_ROUTE}
OWNED_RULE_CREATED=${ADDED_RULE}
EOF
}

rollback_partial_deploy() {
    [ "$ROLLBACK_ARMED" -eq 1 ] || return 0
    ROLLBACK_ARMED=0
    err "Deployment failed partway; rolling back ONLY owned resources created by this run..."

    if [ "$ADDED_RULE" -eq 1 ]; then
        ip rule del from "$WG_SUBNET" table "$WG_TABLE" 2>/dev/null || true
    fi
    if [ "$ADDED_ROUTE" -eq 1 ]; then
        ip route del "$WG_SUBNET" dev "$WG_IFACE" table "$WG_TABLE" 2>/dev/null || true
    fi
    if [ "$CREATED_IFACE" -eq 1 ] || ip link show "$WG_IFACE" >/dev/null 2>&1; then
        ip link del dev "$WG_IFACE" 2>/dev/null || true
    fi
    if [ -n "$OWNED_PID" ]; then
        wg1_stop_owned_pid "$OWNED_PID" "$WG_IFACE" "$PROC_ROOT" || true
    fi
    if [ "$CREATED_PID_FILE" -eq 1 ]; then
        rm -f "$WG_PID_FILE"
    fi
    if [ "$CREATED_LOG_FILE" -eq 1 ]; then
        rm -f "$WG_LOG_FILE"
    fi
    rm -f "${WG_SOCK_DIR}/${WG_IFACE}.sock" "${WG_TMP_DIR}/${WG_IFACE}.sock"
    if [ "$CREATED_BIN" -eq 1 ]; then
        rm -f "$BORINGTUN_BIN"
    fi
    if [ "$CREATED_WG_DIR" -eq 1 ]; then
        rmdir "$WG_DIR" 2>/dev/null || true
    fi
    if [ "$CREATED_TMP_DIR" -eq 1 ]; then
        rmdir "$WG_TMP_DIR" 2>/dev/null || true
    fi
    if [ "$CREATED_SOCK_DIR" -eq 1 ]; then
        rmdir "$WG_SOCK_DIR" 2>/dev/null || true
    fi
    rm -f "$WG_MANIFEST"
}

on_deploy_exit() {
    _rc=$?
    if [ "$_rc" -ne 0 ] && [ "$ROLLBACK_ARMED" -eq 1 ]; then
        rollback_partial_deploy
    fi
    exit "$_rc"
}
trap on_deploy_exit EXIT

# 2. Pure Read-Only Preflight Checks (zero writes/copies before DRY_RUN check)
log "Executing read-only preflight isolation & collision checks..."

if [ -e "$WG_MANIFEST" ]; then
    err "Existing wg1 manifest found at $WG_MANIFEST! Run teardown_wg1.sh first."
    exit 1
fi

if [ -e "$WG_PID_FILE" ]; then
    err "Existing PID file found at $WG_PID_FILE! Run teardown_wg1.sh or verify stale PID first."
    exit 1
fi

if ip link show "$WG_IFACE" >/dev/null 2>&1; then
    err "Interface $WG_IFACE already exists! Run teardown_wg1.sh first."
    exit 1
fi

# Port collision check across netstat / ss / /proc/net/udp
if command -v ss >/dev/null 2>&1 && ss -unlp 2>/dev/null | grep -qE ":${WG_PORT}[[:space:]]"; then
    err "UDP port $WG_PORT is already bound (detected by ss)!"
    exit 1
fi
if command -v netstat >/dev/null 2>&1 && netstat -unl 2>/dev/null | grep -qE ":${WG_PORT}[[:space:]]"; then
    err "UDP port $WG_PORT is already bound (detected by netstat)!"
    exit 1
fi
if [ -r "${PROC_ROOT}/net/udp" ]; then
    _hex_port=$(printf '%04X' "$WG_PORT")
    if awk -v hp=":$_hex_port" 'NR>1 && index($2, hp) {found=1} END{exit !found}' "${PROC_ROOT}/net/udp" 2>/dev/null; then
        err "UDP port $WG_PORT is already bound (detected in ${PROC_ROOT}/net/udp)!"
        exit 1
    fi
fi

# IP / subnet / table / rule collision checks
if ip addr show 2>/dev/null | grep -qF " ${WG_SERVER_ADDR}/"; then
    err "IP address ${WG_SERVER_ADDR} is already configured on an interface!"
    exit 1
fi

if [ -n "$(ip route show table "$WG_TABLE" 2>/dev/null || true)" ]; then
    err "Routing table $WG_TABLE already contains entries! Refusing to clobber shared table."
    exit 1
fi

if ip rule show 2>/dev/null | grep -qE "(from ${WG_SUBNET}|lookup ${WG_TABLE}([[:space:]]|$))"; then
    err "Policy routing rule already exists for subnet $WG_SUBNET or table $WG_TABLE!"
    exit 1
fi

# Resolve BoringTun binary WITHOUT creating dirs or copying files yet
RESOLVED_SRC=""
BIN_ALREADY_INSTALLED=0
if [ -x "$BORINGTUN_BIN" ]; then
    RESOLVED_SRC="$BORINGTUN_BIN"
    BIN_ALREADY_INSTALLED=1
elif [ -x "$STAGED_SRC" ]; then
    RESOLVED_SRC="$STAGED_SRC"
elif [ -x "$REPO_ARTIFACT_BIN" ]; then
    RESOLVED_SRC="$REPO_ARTIFACT_BIN"
else
    err "BoringTun ARMv7 binary not found at $BORINGTUN_BIN, $STAGED_SRC, or $REPO_ARTIFACT_BIN"
    exit 1
fi

# Snapshot production wg0 baseline BEFORE any dry-run exit or live work
WG0_PRE_SNAPSHOT=$(wg1_capture_wg0_fingerprint "$WG_TABLE" "$PROC_ROOT")
if ip link show wg0 >/dev/null 2>&1; then
    log "Pre-deploy wg0 state captured (ACTIVE)."
else
    log "[INFO] Pre-deploy wg0 interface absent (mock or disabled); invariance snapshot recorded."
fi

log "Preflight checks passed. Binary source: $RESOLVED_SRC"

if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN SUMMARY (ZERO FILESYSTEM OR NETWORK MUTATIONS PERFORMED):"
    log "  Interface:   $WG_IFACE (MTU 1420, IP $WG_SERVER_IP, UDP $WG_PORT)"
    log "  Binary src:  $RESOLVED_SRC -> $BORINGTUN_BIN (already_present=$BIN_ALREADY_INSTALLED)"
    log "  Policy net:  route $WG_SUBNET table $WG_TABLE; rule from $WG_SUBNET lookup $WG_TABLE"
    log "  Manifest:    $WG_MANIFEST"
    exit 0
fi

# 3. Begin Atomic Owned Deployment
ROLLBACK_ARMED=1

if [ "$BIN_ALREADY_INSTALLED" -eq 0 ]; then
    if [ ! -d "$WG_DIR" ]; then
        mkdir -p "$WG_DIR"
        CREATED_WG_DIR=1
    fi
    cp "$RESOLVED_SRC" "$BORINGTUN_BIN"
    chmod +x "$BORINGTUN_BIN"
    CREATED_BIN=1
fi

if [ ! -d "$WG_SOCK_DIR" ]; then
    mkdir -p "$WG_SOCK_DIR"
    CREATED_SOCK_DIR=1
fi
if [ ! -d "$WG_TMP_DIR" ]; then
    mkdir -p "$WG_TMP_DIR"
    CREATED_TMP_DIR=1
fi

# 4. Launch BoringTun Daemon
log "Launching BoringTun daemon on interface $WG_IFACE (Port $WG_PORT UDP)..."
: > "$WG_LOG_FILE"
CREATED_LOG_FILE=1

export WG_SUDO=1
"$BORINGTUN_BIN" \
    --disable-drop-privileges \
    --foreground \
    --threads 2 \
    --verbosity debug \
    "$WG_IFACE" > "$WG_LOG_FILE" 2>&1 &

OWNED_PID=$!
echo "$OWNED_PID" > "$WG_PID_FILE"
CREATED_PID_FILE=1
write_manifest "STARTING_DAEMON"
log "BoringTun launched with PID $OWNED_PID (recorded in $WG_PID_FILE)."

# Wait up to 3s for TUN interface AND verify daemon stayed alive
TUN_OK=0
for _i in 1 2 3 4 5 6; do
    if ! kill -0 "$OWNED_PID" 2>/dev/null; then
        err "BoringTun daemon PID $OWNED_PID exited prematurely!"
        cat "$WG_LOG_FILE" >&2 || true
        exit 1
    fi
    if ip link show "$WG_IFACE" >/dev/null 2>&1; then
        TUN_OK=1
        break
    fi
    sleep 0.5
done

if [ "$TUN_OK" -ne 1 ]; then
    err "TUN device $WG_IFACE failed to appear within 3s!"
    cat "$WG_LOG_FILE" >&2 || true
    exit 1
fi
CREATED_IFACE=1
write_manifest "TUN_UP"

# 5. Configure Network Parameters (strict failure check, zero || true)
log "Configuring IP address $WG_SERVER_IP and MTU 1420 on $WG_IFACE..."
ip addr add "$WG_SERVER_IP" dev "$WG_IFACE"
ip link set mtu 1420 up dev "$WG_IFACE"

# 6. Configure Isolated Routing Policy (strict error propagation, zero || true)
log "Configuring isolated routing table $WG_TABLE for $WG_SUBNET..."
ip route add "$WG_SUBNET" dev "$WG_IFACE" proto kernel scope link src "$WG_SERVER_ADDR" table "$WG_TABLE"
ADDED_ROUTE=1
write_manifest "ROUTE_ADDED"

ip rule add from "$WG_SUBNET" table "$WG_TABLE"
ADDED_RULE=1
write_manifest "ACTIVE"

# 7. Final Post-Deploy Production wg0 Invariance Verification
WG0_POST_SNAPSHOT=$(wg1_capture_wg0_fingerprint "$WG_TABLE" "$PROC_ROOT")
if [ "$WG0_PRE_SNAPSHOT" != "$WG0_POST_SNAPSHOT" ]; then
    err "CRITICAL: Production wg0 state or unrelated policy rules changed during wg1 deploy!"
    exit 1
fi

ROLLBACK_ARMED=0
log "Production wg0 invariance verified (100% UNTOUCHED)."
log "BoringTun wg1 status: UP and READY (PID: $OWNED_PID, Manifest: $WG_MANIFEST)"
grep -E "(VmRSS|VmHWM|VmSize)" "${PROC_ROOT}/${OWNED_PID}/status" 2>/dev/null || true
log "Deployment complete."
