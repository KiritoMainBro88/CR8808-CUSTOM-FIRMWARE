#!/bin/sh
# performance/wireguard_rust/wg1_common.sh
# Shared safety, snapshot, manifest, and process-ownership helpers for wg1 BoringTun lifecycle.

wg1_guard_production() {
    _iface="$1"
    _port="$2"
    _subnet="$3"
    _server_ip="$4"

    if [ "$_iface" = "wg0" ]; then
        echo "[CRITICAL SAFETY GUARD] Refusing operation targeting production interface 'wg0'! Aborting." >&2
        exit 99
    fi
    if [ "$_port" = "51820" ]; then
        echo "[CRITICAL SAFETY GUARD] Refusing port 51820 reserved for production wg0! Aborting." >&2
        exit 99
    fi
    if [ "$_subnet" = "10.99.0.0/24" ]; then
        echo "[CRITICAL SAFETY GUARD] Refusing subnet 10.99.0.0/24 reserved for production wg0! Aborting." >&2
        exit 99
    fi
    case "$_server_ip" in
        10.99.0.*)
            echo "[CRITICAL SAFETY GUARD] Refusing IP $_server_ip inside production wg0 range! Aborting." >&2
            exit 99
            ;;
    esac
}

# Safely read single KEY=VALUE from manifest without sourcing arbitrary shell code
wg1_manifest_get() {
    _key="$1"
    _file="$2"
    [ -f "$_file" ] && [ -r "$_file" ] || return 1
    grep -m1 "^${_key}=" "$_file" 2>/dev/null | sed "s/^${_key}=//"
}

# Capture deterministic fingerprint of production wg0 + non-wg1 rules
wg1_capture_wg0_fingerprint() {
    _tbl="${1:-101}"
    _proc_root="${2:-/proc}"
    _wg0_link=$(ip link show dev wg0 2>/dev/null || echo "WG0_LINK_ABSENT")
    _wg0_addr=$(ip addr show dev wg0 2>/dev/null || echo "WG0_ADDR_ABSENT")
    _wg0_route=$(ip route show dev wg0 2>/dev/null || echo "WG0_ROUTE_ABSENT")
    _other_rules=$(ip rule show 2>/dev/null | grep -v "lookup ${_tbl}$" | grep -v "lookup ${_tbl} " || echo "NO_OTHER_RULES")
    _wg_pid=""
    if command -v pidof >/dev/null 2>&1; then
        _wg_pid=$(pidof wg_server 2>/dev/null || echo "")
    fi
    printf 'LINK=%s\nADDR=%s\nROUTE=%s\nRULES=%s\nPID=%s\n' \
        "$_wg0_link" "$_wg0_addr" "$_wg0_route" "$_other_rules" "$_wg_pid"
}

# Verify PID cmdline belongs to boringtun for the expected interface (prevents recycled-PID kills)
wg1_pid_matches_owned() {
    _pid="$1"
    _iface="$2"
    _proc_root="${3:-/proc}"

    [ -n "$_pid" ] || return 1
    _cmdline_file="${_proc_root}/${_pid}/cmdline"
    if [ -r "$_cmdline_file" ]; then
        _cmd=$(tr '\0' ' ' < "$_cmdline_file" 2>/dev/null || echo "")
        case "$_cmd" in
            *boringtun*"$_iface"*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 1
}

# Terminate strictly the owned PID (never pkill -f); returns 0 if dead/absent/recycled, 1 if still alive
wg1_stop_owned_pid() {
    _pid="$1"
    _iface="$2"
    _proc_root="${3:-/proc}"
    _kill_hook="${WG_PID_KILL_CHECK:-}"

    [ -n "$_pid" ] || return 0
    if ! kill -0 "$_pid" 2>/dev/null; then
        return 0
    fi

    if ! wg1_pid_matches_owned "$_pid" "$_iface" "$_proc_root"; then
        echo "[wg1-guard] WARN: Recorded PID $_pid cmdline does not match boringtun+$_iface (recycled PID); refusing kill." >&2
        return 0
    fi

    kill -TERM "$_pid" 2>/dev/null || true
    for _i in 1 2 3; do
        if ! kill -0 "$_pid" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done

    kill -KILL "$_pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$_pid" 2>/dev/null; then
        echo "[wg1-guard] ERROR: Owned PID $_pid is still alive after SIGTERM and SIGKILL!" >&2
        return 1
    fi
    return 0
}
