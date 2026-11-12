#!/bin/sh
# performance/profiles/netdev_backlog.sh
# ==============================================================================
# Profile: Network Backlog & Ring Buffer Polling Tuning
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
#
# SPECIFICATION & ARCHITECTURAL DOCUMENTATION:
# ------------------------------------------------------------------------------
# 1. PARAMETERS & VALUES:
#    - net.core.netdev_max_backlog:
#        Baseline: 10000 -> Proposed: 16384
#    - net.core.netdev_budget:
#        Baseline: 300 -> Proposed: 600
#    - net.core.netdev_budget_usecs:
#        Baseline: 2000 (if present) -> Proposed: 4000
#
# 2. HARDWARE COMPATIBILITY:
#    - Architecture: Linux 4.4.60 networking core.
#    - Compatible with all IPQ5018 Ethernet (SGMII) and Wi-Fi interfaces.
#
# 3. RAM & CPU COST:
#    - RAM: Expanding netdev_max_backlog from 10,000 to 16,384 uses ~25 KiB for
#      sk_buff pointer descriptors.
#    - CPU: Increasing netdev_budget to 600 allows NAPI polling routines to drain
#      device ring buffers in fewer softirq cycles, reducing interrupt reschedule
#      overhead and preventing ring overflow drops during Gigabit bursts.
#
# 4. FAILURE MODES & MITIGATIONS:
#    - Failure Mode: Starvation of userspace tasks if netdev_budget is set too high.
#      Mitigation: Capped at 600 packets / 4000 usecs (safe for 1.0 GHz dual A53).
#    - Failure Mode: netdev_budget_usecs unsupported in older kernel versions.
#      Mitigation: Optional parameter; checked before applying.
# ==============================================================================

set -u

PROFILE_NAME="netdev_backlog"
PROFILE_DESC="Network Device Input Backlog & NAPI Polling Budget Tuning"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_LIB="${SCRIPT_DIR}/../lib"
. "${FRAMEWORK_LIB}/common.sh"

PROPOSED_BACKLOG="16384"
PROPOSED_BUDGET="600"
PROPOSED_BUDGET_USECS="4000"

info() {
    cat << 'EOF'
Profile: netdev_backlog
Description: Network Device Input Backlog & NAPI Polling Budget Tuning
Parameters:
  - net.core.netdev_max_backlog: 10000 -> 16384
  - net.core.netdev_budget: 300 -> 600
  - net.core.netdev_budget_usecs: 2000 -> 4000 (if supported)
Hardware Compatibility: Linux 4.4.60 networking core, IPQ5018
RAM Cost: ~25 KiB
CPU Impact: Reduces NAPI softirq scheduling overhead; eliminates ring drops during microbursts
Failure Modes: Excessive budget could starve userspace (mitigated by 600 packet cap)
EOF
}

audit() {
    log_info "Auditing profile: ${PROFILE_NAME}"
    _cur_backlog=$(read_sysctl "net.core.netdev_max_backlog" || echo "UNKNOWN")
    _cur_budget=$(read_sysctl "net.core.netdev_budget" || echo "UNKNOWN")
    _cur_budget_usecs=$(read_sysctl "net.core.netdev_budget_usecs" || echo "NOT_SUPPORTED")

    echo "  [sysctl] net.core.netdev_max_backlog: Current=$_cur_backlog | Proposed=$PROPOSED_BACKLOG"
    echo "  [sysctl] net.core.netdev_budget: Current=$_cur_budget | Proposed=$PROPOSED_BUDGET"
    echo "  [sysctl] net.core.netdev_budget_usecs: Current=$_cur_budget_usecs | Proposed=$PROPOSED_BUDGET_USECS"
}

apply() {
    log_info "Applying profile: ${PROFILE_NAME}"
    ensure_state_dir

    if has_state "$PROFILE_NAME"; then
        log_warn "State snapshot already exists for ${PROFILE_NAME}. Rollback first before re-applying."
        return 1
    fi

    # Snapshot current values
    _orig_backlog=$(read_sysctl "net.core.netdev_max_backlog" || echo "10000")
    _orig_budget=$(read_sysctl "net.core.netdev_budget" || echo "300")
    save_state_kv "$PROFILE_NAME" "sysctl.net.core.netdev_max_backlog" "$_orig_backlog"
    save_state_kv "$PROFILE_NAME" "sysctl.net.core.netdev_budget" "$_orig_budget"

    if _orig_budget_usecs=$(read_sysctl "net.core.netdev_budget_usecs"); then
        save_state_kv "$PROFILE_NAME" "sysctl.net.core.netdev_budget_usecs" "$_orig_budget_usecs"
    fi

    # Apply proposed values
    if ! write_sysctl "net.core.netdev_max_backlog" "$PROPOSED_BACKLOG"; then
        log_err "Failed to write net.core.netdev_max_backlog"
        rollback
        return 1
    fi

    if ! write_sysctl "net.core.netdev_budget" "$PROPOSED_BUDGET"; then
        log_err "Failed to write net.core.netdev_budget"
        rollback
        return 1
    fi

    # Attempt optional budget_usecs
    write_sysctl "net.core.netdev_budget_usecs" "$PROPOSED_BUDGET_USECS" 2>/dev/null || true

    if verify; then
        log_success "Profile ${PROFILE_NAME} applied successfully."
        return 0
    else
        log_err "Profile ${PROFILE_NAME} verification failed after apply. Initiating automatic rollback."
        rollback
        return 1
    fi
}

rollback() {
    log_info "Rolling back profile: ${PROFILE_NAME}"
    _state_file=$(get_state_file "$PROFILE_NAME")
    if [ ! -f "$_state_file" ]; then
        log_warn "No state file found for ${PROFILE_NAME}. Nothing to rollback."
        return 0
    fi

    while IFS='=' read -r key val || [ -n "$key" ]; do
        case "$key" in
            sysctl.*)
                _param=$(echo "$key" | sed 's/^sysctl\.//')
                write_sysctl "$_param" "$val" || log_warn "Failed to restore sysctl $_param"
                ;;
        esac
    done < "$_state_file"

    clear_state "$PROFILE_NAME"
    log_success "Profile ${PROFILE_NAME} rolled back successfully."
    return 0
}

verify() {
    _cur_backlog=$(read_sysctl "net.core.netdev_max_backlog" || echo "")
    _cur_budget=$(read_sysctl "net.core.netdev_budget" || echo "")
    if [ "$_cur_backlog" != "$PROPOSED_BACKLOG" ] || [ "$_cur_budget" != "$PROPOSED_BUDGET" ]; then
        return 1
    fi
    return 0
}

ACTION="${1:-info}"
case "$ACTION" in
    info) info ;;
    audit) audit ;;
    apply) apply ;;
    rollback) rollback ;;
    verify) verify ;;
    *)
        echo "Usage: $0 {info|audit|apply|rollback|verify}"
        exit 1
        ;;
esac
