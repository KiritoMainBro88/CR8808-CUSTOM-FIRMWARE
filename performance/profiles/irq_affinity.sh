#!/bin/sh
# performance/profiles/irq_affinity.sh
# ==============================================================================
# Profile: Hardware IRQ Affinity Balancing
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
#
# SPECIFICATION & ARCHITECTURAL DOCUMENTATION:
# ------------------------------------------------------------------------------
# 1. PARAMETERS & VALUES:
#    - Wi-Fi 5GHz PCIe Copy Engine 1 (pci0_wlan_ce_1):
#        Baseline: 1 (CPU0) -> Proposed: 2 (CPU1 affinity mask 0x2)
#    - Wi-Fi 5GHz PCIe Copy Engine 2 (pci0_wlan_ce_2):
#        Baseline: 1 (CPU0) -> Proposed: 2 (CPU1 affinity mask 0x2)
#    - Wi-Fi 5GHz Data Path 3 (pci0_wlan_grp_dp_3):
#        Baseline: 1 (CPU0) -> Proposed: 2 (CPU1 affinity mask 0x2)
#    - Hardware Crypto Engine 2 (ce2):
#        Baseline: 1 (CPU0) -> Proposed: 2 (CPU1 affinity mask 0x2)
#
# 2. HARDWARE COMPATIBILITY:
#    - Architecture: ARM Cortex-A53 Dual-Core (IPQ5018) with ARM GIC-400 interrupt
#      controller supporting dynamic SPI routing via /proc/irq/<irq>/smp_affinity.
#
# 3. RAM & CPU COST:
#    - RAM: 0 bytes.
#    - CPU: Prevents CPU0 IRQ starvation. On RA82, CPU0 previously handled over
#      260M hardware interrupts while CPU1 handled <1M. Moving Wi-Fi 5GHz DMA and
#      crypto interrupts to CPU1 achieves near 50/50 hardware IRQ distribution.
#
# 4. FAILURE MODES & MITIGATIONS:
#    - Failure Mode: Writing affinity to non-routable PPI (per-CPU timer) causes EIO.
#      Mitigation: Dynamically searches /proc/interrupts by peripheral name; only
#      modifies routable SPIs for Wi-Fi and crypto engines.
#    - Failure Mode: IRQ numbers vary across kernel revisions.
#      Mitigation: Name-based IRQ resolution dynamically extracts the active IRQ number.
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
Parameters:
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
            # Affinity mask may be formatted with leading zeros or spaces (e.g. '02' or '2')
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
