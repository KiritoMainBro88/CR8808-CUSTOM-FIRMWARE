#!/bin/sh
# performance/profiles/irq_affinity.sh
# ==============================================================================
# Profile: Hardware IRQ Affinity Balancing across CPU0 and CPU1
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
#
# SPECIFICATION & MEASURABLE ACCEPTANCE CRITERIA:
# ------------------------------------------------------------------------------
# 1. BASELINE CONFLICT & MEASUREMENTS:
#    - Factory Baseline: Over 260,000,000 hardware interrupts accumulated on CPU0,
#      including all Wi-Fi 5GHz DMA rings (35.8M) and Crypto Engines (13.2M),
#      while CPU1 handled only 752K interrupts.
#    - Under sustained Wi-Fi 6 HE160 transmission, CPU0 suffers severe IRQ latency
#      jitter, starving userspace daemons and VPN processing.
#
# 2. MEASURABLE ACCEPTANCE CRITERIA:
#    - [CRIT-1] Wi-Fi 5GHz DMA Affinity: pci0_wlan_ce_1 smp_affinity == 2 (CPU1).
#    - [CRIT-2] Wi-Fi 5GHz Ring Affinity: pci0_wlan_ce_2 smp_affinity == 2 (CPU1).
#    - [CRIT-3] Wi-Fi 5GHz DP Affinity: pci0_wlan_grp_dp_3 smp_affinity == 2 (CPU1).
#    - [CRIT-4] Crypto Offload Affinity: ce2 (Crypto Engine 2) smp_affinity == 2 (CPU1).
#    - [CRIT-5] Dynamic Discovery: Exact IRQ numbers resolved by name from /proc/interrupts.
#    - [CRIT-6] Reversible Rollback: Original affinities (0x1) restored 100% bit-for-bit.
#
# 3. RAM & CPU COST:
#    - RAM: 0 bytes.
#    - CPU: Eliminates single-core interrupt bottlenecks. Distributes high-frequency
#      DMA completion events from 5GHz Wi-Fi directly to CPU1.
#
# 4. FAILURE MODES & MITIGATIONS:
#    - Failure Mode: Writing affinity to non-routable PPI (per-CPU timer) causes EIO.
#      Mitigation: Dynamically queries /proc/interrupts for specific named SPIs only.
# ==============================================================================

set -u

PROFILE_NAME="irq_affinity"
PROFILE_DESC="Hardware IRQ Affinity Balancing across CPU0 and CPU1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_LIB="${SCRIPT_DIR}/../lib"
. "${FRAMEWORK_LIB}/common.sh"

TARGET_NAMES="pci0_wlan_ce_1 pci0_wlan_ce_2 pci0_wlan_grp_dp_3 ce2"
PROPOSED_CPU1_MASK="2"

# Find IRQ number by device name in /proc/interrupts
find_irq_by_name() {
    _name="$1"
    _proc_int="${MOCK_ROOT}/proc/interrupts"
    if [ -f "$_proc_int" ]; then
        grep "[[:space:]]${_name}$" "$_proc_int" 2>/dev/null | awk '{print $1}' | tr -d ':' | head -n 1
    fi
}

info() {
    cat << 'EOF'
Profile: irq_affinity
Description: Hardware IRQ Affinity Balancing across CPU0 and CPU1
Measurable Acceptance Criteria:
  - pci0_wlan_ce_1 smp_affinity: 1 -> 2 (CPU1)
  - pci0_wlan_ce_2 smp_affinity: 1 -> 2 (CPU1)
  - pci0_wlan_grp_dp_3 smp_affinity: 1 -> 2 (CPU1)
  - ce2 (Crypto Engine 2) smp_affinity: 1 -> 2 (CPU1)
Hardware Compatibility: Qualcomm IPQ5018 GIC-400, Linux 4.4.60 QSDK
RAM Cost: 0 bytes
CPU Impact: Eliminates single-core IRQ bottleneck during HE160 Wi-Fi 6 transmission
Failure Modes: Non-routable IRQ write error (mitigated by name-based SPI discovery)
EOF
}

audit() {
    log_info "Auditing profile: ${PROFILE_NAME}"
    for name in $TARGET_NAMES; do
        _irq=$(find_irq_by_name "$name")
        if [ -n "$_irq" ]; then
            _aff_path="/proc/irq/${_irq}/smp_affinity"
            _cur=$(read_sysfs "$_aff_path" || echo "UNKNOWN")
            echo "  [irq] $name (IRQ $_irq): Current=$_cur | Proposed=$PROPOSED_CPU1_MASK"
        else
            echo "  [irq] $name: NOT FOUND in /proc/interrupts"
        fi
    done
}

apply() {
    log_info "Applying profile: ${PROFILE_NAME}"
    ensure_state_dir

    if has_state "$PROFILE_NAME"; then
        log_warn "State snapshot already exists for ${PROFILE_NAME}. Rollback first before re-applying."
        return 1
    fi

    _applied_count=0
    for name in $TARGET_NAMES; do
        _irq=$(find_irq_by_name "$name")
        if [ -n "$_irq" ]; then
            _aff_path="/proc/irq/${_irq}/smp_affinity"
            _orig=$(read_sysfs "$_aff_path" || echo "1")
            save_state_kv "$PROFILE_NAME" "irq.${_irq}.${name}" "$_orig"
            if write_sysfs "$_aff_path" "$PROPOSED_CPU1_MASK"; then
                _applied_count=$((_applied_count + 1))
            else
                log_warn "Failed to set smp_affinity for IRQ $_irq ($name)"
            fi
        fi
    done

    if [ "$_applied_count" -eq 0 ]; then
        log_warn "No target IRQs were found to steer. Saving empty state snapshot."
    fi

    if verify; then
        log_success "Profile ${PROFILE_NAME} applied successfully ($_applied_count IRQs steered)."
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
            irq.*)
                _irq=$(echo "$key" | cut -d'.' -f2)
                _aff_path="/proc/irq/${_irq}/smp_affinity"
                write_sysfs "$_aff_path" "$val" || log_warn "Failed to restore IRQ $_irq smp_affinity"
                ;;
        esac
    done < "$_state_file"

    clear_state "$PROFILE_NAME"
    log_success "Profile ${PROFILE_NAME} rolled back successfully."
    return 0
}

verify() {
    for name in $TARGET_NAMES; do
        _irq=$(find_irq_by_name "$name")
        if [ -n "$_irq" ]; then
            _aff_path="/proc/irq/${_irq}/smp_affinity"
            _cur=$(read_sysfs "$_aff_path" || echo "")
            _cur_dec=$(echo "$_cur" | tr -d ' ' | sed 's/^0*//')
            if [ -z "$_cur_dec" ]; then _cur_dec="0"; fi
            if [ "$_cur_dec" != "$PROPOSED_CPU1_MASK" ]; then
                return 1
            fi
        fi
    done
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
