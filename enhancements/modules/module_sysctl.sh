#!/bin/sh
# enhancements/modules/module_sysctl.sh
# ==============================================================================
# Module: TCP Socket Lifecycles, FastOpen, and Conntrack Table Optimization
# Workstream B & F: Network Performance Optimization
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53)
# ==============================================================================

set -u

MOCK_ROOT="${MOCK_ROOT:-}"

describe() {
    echo "Sysctl networking tuning: Enables TCP FastOpen (TFO 3), tw_reuse, shortens"
    echo "TIME_WAIT to 30s, and reclaims idle conntrack entries (86400s established)."
}

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
        cat "$_path" 2>/dev/null | tr -d ' \t\r\n'
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
    _state_file="${_target_dir}/state/module_sysctl.state"
    mkdir -p "${_target_dir}/state" "${_target_dir}/bin" 2>/dev/null || true

    _orig_tfo=$(read_node "/proc/sys/net/ipv4/tcp_fastopen")
    _orig_reuse=$(read_node "/proc/sys/net/ipv4/tcp_tw_reuse")
    _orig_fin=$(read_node "/proc/sys/net/ipv4/tcp_fin_timeout")
    _orig_ct=$(read_node "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established")

    cat << EOF > "$_state_file"
ORIG_TCP_FASTOPEN=${_orig_tfo:-0}
ORIG_TCP_TW_REUSE=${_orig_reuse:-0}
ORIG_TCP_FIN_TIMEOUT=${_orig_fin:-60}
ORIG_CONNTRACK_TIMEOUT=${_orig_ct:-432000}
EOF

    write_node "/proc/sys/net/ipv4/tcp_fastopen" "3" || true
    write_node "/proc/sys/net/ipv4/tcp_tw_reuse" "1" || true
    write_node "/proc/sys/net/ipv4/tcp_fin_timeout" "30" || true
    write_node "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" "86400" || true

    cat << 'EOF' > "${_target_dir}/bin/module_sysctl_apply.sh"
#!/bin/sh
MOCK_ROOT="${MOCK_ROOT:-}"
_w() {
    _p="${MOCK_ROOT}$1"
    if [ -n "$MOCK_ROOT" ]; then mkdir -p "$(dirname "$_p")" 2>/dev/null || true; fi
    if [ -w "$_p" ] || [ -n "$MOCK_ROOT" ]; then printf '%s\n' "$2" > "$_p" 2>/dev/null || true; fi
}
_w "/proc/sys/net/ipv4/tcp_fastopen" "3"
_w "/proc/sys/net/ipv4/tcp_tw_reuse" "1"
_w "/proc/sys/net/ipv4/tcp_fin_timeout" "30"
_w "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" "86400"
EOF
    chmod +x "${_target_dir}/bin/module_sysctl_apply.sh" 2>/dev/null || true

    cat << EOF > "${_target_dir}/bin/module_sysctl_rollback.sh"
#!/bin/sh
MOCK_ROOT="\${MOCK_ROOT:-}"
_w() {
    _p="\${MOCK_ROOT}\$1"
    if [ -n "\$MOCK_ROOT" ]; then mkdir -p "\$(dirname "\$_p")" 2>/dev/null || true; fi
    if [ -w "\$_p" ] || [ -n "\$MOCK_ROOT" ]; then printf '%s\n' "\$2" > "\$_p" 2>/dev/null || true; fi
}
_w "/proc/sys/net/ipv4/tcp_fastopen" "${_orig_tfo:-0}"
_w "/proc/sys/net/ipv4/tcp_tw_reuse" "${_orig_reuse:-0}"
_w "/proc/sys/net/ipv4/tcp_fin_timeout" "${_orig_fin:-60}"
_w "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" "${_orig_ct:-432000}"
EOF
    chmod +x "${_target_dir}/bin/module_sysctl_rollback.sh" 2>/dev/null || true

    return 0
}

rollback() {
    _target_dir="$1"
    _state_file="${_target_dir}/state/module_sysctl.state"

    _orig_tfo="0"
    _orig_reuse="0"
    _orig_fin="60"
    _orig_ct="432000"
    if [ -f "$_state_file" ]; then
        _orig_tfo=$(grep "^ORIG_TCP_FASTOPEN=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "0")
        _orig_reuse=$(grep "^ORIG_TCP_TW_REUSE=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "0")
        _orig_fin=$(grep "^ORIG_TCP_FIN_TIMEOUT=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "60")
        _orig_ct=$(grep "^ORIG_CONNTRACK_TIMEOUT=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "432000")
    fi

    write_node "/proc/sys/net/ipv4/tcp_fastopen" "${_orig_tfo:-0}" || true
    write_node "/proc/sys/net/ipv4/tcp_tw_reuse" "${_orig_reuse:-0}" || true
    write_node "/proc/sys/net/ipv4/tcp_fin_timeout" "${_orig_fin:-60}" || true
    write_node "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" "${_orig_ct:-432000}" || true

    rm -f "$_state_file" "${_target_dir}/bin/module_sysctl_apply.sh" "${_target_dir}/bin/module_sysctl_rollback.sh" 2>/dev/null || true
    return 0
}

verify() {
    _tfo=$(read_node "/proc/sys/net/ipv4/tcp_fastopen")
    _reuse=$(read_node "/proc/sys/net/ipv4/tcp_tw_reuse")
    _fin=$(read_node "/proc/sys/net/ipv4/tcp_fin_timeout")
    _ct=$(read_node "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established")

    if [ "$_tfo" = "3" ] && [ "$_reuse" = "1" ] && [ "$_fin" = "30" ] && [ "$_ct" = "86400" ]; then
        return 0
    fi
    return 1
}

status() {
    echo "  Module: module_sysctl"
    echo "    tcp_fastopen:      $(read_node "/proc/sys/net/ipv4/tcp_fastopen") (Target: 3)"
    echo "    tcp_tw_reuse:      $(read_node "/proc/sys/net/ipv4/tcp_tw_reuse") (Target: 1)"
    echo "    tcp_fin_timeout:   $(read_node "/proc/sys/net/ipv4/tcp_fin_timeout") (Target: 30)"
    echo "    conntrack_timeout: $(read_node "/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established") (Target: 86400)"
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
