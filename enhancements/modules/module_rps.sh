#!/bin/sh
# enhancements/modules/module_rps.sh
# ==============================================================================
# Module: Receive Packet Steering (RPS) & Receive Flow Steering (RFS)
# Workstream B & F: Network Performance Optimization
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53)
# ==============================================================================

set -u

MOCK_ROOT="${MOCK_ROOT:-}"

describe() {
    echo "RPS/RFS queue steering optimization: Steers eth0 rx-0 softirqs to CPU1 (0x2)"
    echo "and balances eth1/br-lan across dual cores. Offloads CPU0 for NSS and crypto."
}

# Resolve sysfs/proc path with MOCK_ROOT
resolve_path() {
    _rel="$1"
    case "$_rel" in
        "$MOCK_ROOT"*) echo "$_rel" ;;
        *) echo "${MOCK_ROOT}${_rel}" ;;
    esac
}

read_node() {
    _path=$(resolve_path "$1")
    if [ -f "$_path" ]; then
        _val=$(cat "$_path" 2>/dev/null | tr -d ' \t\r\n' | sed 's/^0*//')
        if [ -z "$_val" ]; then echo "0"; else echo "$_val"; fi
        return 0
    fi
    echo ""
    return 1
}

write_node() {
    _rel="$1"
    _val="$2"
    _path=$(resolve_path "$_rel")
    if [ -n "$MOCK_ROOT" ]; then
        mkdir -p "$(dirname "$_path")" 2>/dev/null || true
        printf '%s\n' "$_val" > "$_path" 2>/dev/null || return 1
        return 0
    elif [ -w "$_path" ]; then
        printf '%s\n' "$_val" > "$_path" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

apply() {
    _target_dir="$1"
    _state_file="${_target_dir}/state/module_rps.state"
    mkdir -p "${_target_dir}/state" "${_target_dir}/bin" 2>/dev/null || true

    # Snapshot current values
    _orig_eth0=$(read_node "/sys/class/net/eth0/queues/rx-0/rps_cpus")
    _orig_sock_flow=$(read_node "/proc/sys/net/core/rps_sock_flow_entries")

    cat << EOF > "$_state_file"
ORIG_ETH0_RPS=${_orig_eth0:-0}
ORIG_SOCK_FLOW=${_orig_sock_flow:-0}
EOF

    # Apply tunings
    write_node "/sys/class/net/eth0/queues/rx-0/rps_cpus" "2" || true
    write_node "/proc/sys/net/core/rps_sock_flow_entries" "16384" || true

    # Optional interfaces if present
    _eth1_path=$(resolve_path "/sys/class/net/eth1/queues/rx-0/rps_cpus")
    if [ -f "$_eth1_path" ]; then
        write_node "/sys/class/net/eth1/queues/rx-0/rps_cpus" "3" || true
    fi

    _brlan_path=$(resolve_path "/sys/class/net/br-lan/queues/rx-0/rps_cpus")
    if [ -f "$_brlan_path" ]; then
        write_node "/sys/class/net/br-lan/queues/rx-0/rps_cpus" "3" || true
    fi

    _eth0_cnt_path=$(resolve_path "/sys/class/net/eth0/queues/rx-0/rps_flow_cnt")
    if [ -f "$_eth0_cnt_path" ]; then
        write_node "/sys/class/net/eth0/queues/rx-0/rps_flow_cnt" "4096" || true
    fi

    # Create apply & rollback scripts for startup hook
    cat << 'EOF' > "${_target_dir}/bin/module_rps_apply.sh"
#!/bin/sh
MOCK_ROOT="${MOCK_ROOT:-}"
_w() {
    _p="${MOCK_ROOT}$1"
    if [ -n "$MOCK_ROOT" ]; then mkdir -p "$(dirname "$_p")" 2>/dev/null || true; fi
    if [ -w "$_p" ] || [ -n "$MOCK_ROOT" ]; then printf '%s\n' "$2" > "$_p" 2>/dev/null || true; fi
}
_w "/sys/class/net/eth0/queues/rx-0/rps_cpus" "2"
_w "/proc/sys/net/core/rps_sock_flow_entries" "16384"
_w "/sys/class/net/eth1/queues/rx-0/rps_cpus" "3"
_w "/sys/class/net/br-lan/queues/rx-0/rps_cpus" "3"
EOF
    chmod +x "${_target_dir}/bin/module_rps_apply.sh" 2>/dev/null || true

    cat << EOF > "${_target_dir}/bin/module_rps_rollback.sh"
#!/bin/sh
MOCK_ROOT="\${MOCK_ROOT:-}"
_w() {
    _p="\${MOCK_ROOT}\$1"
    if [ -n "\$MOCK_ROOT" ]; then mkdir -p "\$(dirname "\$_p")" 2>/dev/null || true; fi
    if [ -w "\$_p" ] || [ -n "\$MOCK_ROOT" ]; then printf '%s\n' "\$2" > "\$_p" 2>/dev/null || true; fi
}
_w "/sys/class/net/eth0/queues/rx-0/rps_cpus" "${_orig_eth0:-0}"
_w "/proc/sys/net/core/rps_sock_flow_entries" "${_orig_sock_flow:-0}"
_w "/sys/class/net/eth1/queues/rx-0/rps_cpus" "0"
_w "/sys/class/net/br-lan/queues/rx-0/rps_cpus" "0"
EOF
    chmod +x "${_target_dir}/bin/module_rps_rollback.sh" 2>/dev/null || true

    return 0
}

rollback() {
    _target_dir="$1"
    _state_file="${_target_dir}/state/module_rps.state"

    _orig_eth0="0"
    _orig_sock_flow="0"
    if [ -f "$_state_file" ]; then
        _orig_eth0=$(grep "^ORIG_ETH0_RPS=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "0")
        _orig_sock_flow=$(grep "^ORIG_SOCK_FLOW=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "0")
    fi

    write_node "/sys/class/net/eth0/queues/rx-0/rps_cpus" "${_orig_eth0:-0}" || true
    write_node "/proc/sys/net/core/rps_sock_flow_entries" "${_orig_sock_flow:-0}" || true

    _eth1_path=$(resolve_path "/sys/class/net/eth1/queues/rx-0/rps_cpus")
    if [ -f "$_eth1_path" ]; then
        write_node "/sys/class/net/eth1/queues/rx-0/rps_cpus" "0" || true
    fi

    _brlan_path=$(resolve_path "/sys/class/net/br-lan/queues/rx-0/rps_cpus")
    if [ -f "$_brlan_path" ]; then
        write_node "/sys/class/net/br-lan/queues/rx-0/rps_cpus" "0" || true
    fi

    rm -f "$_state_file" "${_target_dir}/bin/module_rps_apply.sh" "${_target_dir}/bin/module_rps_rollback.sh" 2>/dev/null || true
    return 0
}

verify() {
    _eth0_val=$(read_node "/sys/class/net/eth0/queues/rx-0/rps_cpus")
    if [ "$_eth0_val" = "2" ]; then
        return 0
    fi
    return 1
}

status() {
    echo "  Module: module_rps"
    echo "    eth0 rps_cpus:        $(read_node "/sys/class/net/eth0/queues/rx-0/rps_cpus") (Target: 2)"
    echo "    rps_sock_flow_entries: $(read_node "/proc/sys/net/core/rps_sock_flow_entries") (Target: 16384)"
}

ACTION="${1:-status}"
shift || true
case "$ACTION" in
    describe) describe ;;
    apply)    apply "$@" ;;
    rollback) rollback "$@" ;;
    verify)   verify "$@" ;;
    status)   status "$@" ;;
    *) echo "Usage: $0 {describe|apply|rollback|verify|status} [target_dir]"; exit 1 ;;
esac
