#!/bin/sh
# enhancements/modules/module_napi.sh
# ==============================================================================
# Module: NAPI Backlog & Ring Buffer Processing Budget Tuning
# Workstream B & F: Network Performance Optimization
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53)
# ==============================================================================

set -u

MOCK_ROOT="${MOCK_ROOT:-}"

describe() {
    echo "NAPI budget tuning: Expands netdev_max_backlog to 16384 and netdev_budget"
    echo "to 600 packets, preventing ring buffer drops under gigabit HE160 bursts."
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
    _state_file="${_target_dir}/state/module_napi.state"
    mkdir -p "${_target_dir}/state" "${_target_dir}/bin" 2>/dev/null || true

    _orig_backlog=$(read_node "/proc/sys/net/core/netdev_max_backlog")
    _orig_budget=$(read_node "/proc/sys/net/core/netdev_budget")

    cat << EOF > "$_state_file"
ORIG_NETDEV_MAX_BACKLOG=${_orig_backlog:-10000}
ORIG_NETDEV_BUDGET=${_orig_budget:-300}
EOF

    write_node "/proc/sys/net/core/netdev_max_backlog" "16384" || true
    write_node "/proc/sys/net/core/netdev_budget" "600" || true

    _budget_usecs_path=$(resolve_path "/proc/sys/net/core/netdev_budget_usecs")
    if [ -f "$_budget_usecs_path" ]; then
        _orig_usecs=$(read_node "/proc/sys/net/core/netdev_budget_usecs")
        echo "ORIG_NETDEV_BUDGET_USECS=${_orig_usecs:-2000}" >> "$_state_file"
        write_node "/proc/sys/net/core/netdev_budget_usecs" "4000" || true
    fi

    # Create apply & rollback scripts for startup hook
    cat << 'EOF' > "${_target_dir}/bin/module_napi_apply.sh"
#!/bin/sh
MOCK_ROOT="${MOCK_ROOT:-}"
_w() {
    _p="${MOCK_ROOT}$1"
    if [ -n "$MOCK_ROOT" ]; then mkdir -p "$(dirname "$_p")" 2>/dev/null || true; fi
    if [ -w "$_p" ] || [ -n "$MOCK_ROOT" ]; then printf '%s\n' "$2" > "$_p" 2>/dev/null || true; fi
}
_w "/proc/sys/net/core/netdev_max_backlog" "16384"
_w "/proc/sys/net/core/netdev_budget" "600"
EOF
    chmod +x "${_target_dir}/bin/module_napi_apply.sh" 2>/dev/null || true

    cat << EOF > "${_target_dir}/bin/module_napi_rollback.sh"
#!/bin/sh
MOCK_ROOT="\${MOCK_ROOT:-}"
_w() {
    _p="\${MOCK_ROOT}\$1"
    if [ -n "\$MOCK_ROOT" ]; then mkdir -p "\$(dirname "\$_p")" 2>/dev/null || true; fi
    if [ -w "\$_p" ] || [ -n "\$MOCK_ROOT" ]; then printf '%s\n' "\$2" > "\$_p" 2>/dev/null || true; fi
}
_w "/proc/sys/net/core/netdev_max_backlog" "${_orig_backlog:-10000}"
_w "/proc/sys/net/core/netdev_budget" "${_orig_budget:-300}"
EOF
    chmod +x "${_target_dir}/bin/module_napi_rollback.sh" 2>/dev/null || true

    return 0
}

rollback() {
    _target_dir="$1"
    _state_file="${_target_dir}/state/module_napi.state"

    _orig_backlog="10000"
    _orig_budget="300"
    if [ -f "$_state_file" ]; then
        _orig_backlog=$(grep "^ORIG_NETDEV_MAX_BACKLOG=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "10000")
        _orig_budget=$(grep "^ORIG_NETDEV_BUDGET=" "$_state_file" 2>/dev/null | cut -d= -f2 || echo "300")
    fi

    write_node "/proc/sys/net/core/netdev_max_backlog" "${_orig_backlog:-10000}" || true
    write_node "/proc/sys/net/core/netdev_budget" "${_orig_budget:-300}" || true

    rm -f "$_state_file" "${_target_dir}/bin/module_napi_apply.sh" "${_target_dir}/bin/module_napi_rollback.sh" 2>/dev/null || true
    return 0
}

verify() {
    _backlog=$(read_node "/proc/sys/net/core/netdev_max_backlog")
    _budget=$(read_node "/proc/sys/net/core/netdev_budget")
    if [ "$_backlog" = "16384" ] && [ "$_budget" = "600" ]; then
        return 0
    fi
    return 1
}

status() {
    echo "  Module: module_napi"
    echo "    netdev_max_backlog: $(read_node "/proc/sys/net/core/netdev_max_backlog") (Target: 16384)"
    echo "    netdev_budget:      $(read_node "/proc/sys/net/core/netdev_budget") (Target: 600)"
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
