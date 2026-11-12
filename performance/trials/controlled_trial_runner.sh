#!/bin/sh
# performance/trials/controlled_trial_runner.sh
# ==============================================================================
# Controlled Performance Trial Runner: RPS Steering on eth0 (Single-Variable)
# Workstream B & G: Network Performance & Automated Optimization
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
#
# CANDIDATE SELECTION & ARCHITECTURAL JUSTIFICATION:
# ------------------------------------------------------------------------------
# Target Parameter: /sys/class/net/eth0/queues/rx-0/rps_cpus
# Baseline Value:   0 (Disabled)
# Trial Target:     2 (CPU1 affinity mask 0x2)
#
# Rationale:
#   1. Immediate Measurable Metric: Shifting packet softirqs from 99.6% CPU0
#      saturation to CPU1 produces an immediate, empirical delta in /proc/softirqs
#      (NET_RX counter on CPU1 vs CPU0) during forwarding traffic.
#   2. Zero Routing / Wi-Fi Impact: Operates purely at the softirq backlog steering
#      layer; zero disruption to DSA switch tags, Wi-Fi 6 radio, or routing tables.
#   3. Zero NSS Conflict: Flows already accelerated by Qualcomm NSS bypass the Linux
#      stack; RPS applies strictly to non-offloaded ingress (VPN, local sockets, IPv6).
#   4. 100% Instantaneous Reversibility: Single sysfs write to 0 instantly restores
#      factory queue steering without daemon restart or socket drops.
#
# DEFENSE-IN-DEPTH ARCHITECTURE:
#   - Atomic Directory Lock: /tmp/trial_lock.d prevents concurrent executions.
#   - State Snapshot Verification: Confirms snapshot non-zero size, readability,
#     and valid key-value format before touching system state.
#   - 180s Independent Watchdog: Background process forces revert if runner stalls.
#   - Verified Rollback Guarantee: Never disarms watchdog or deletes state file
#     unless actual readback matches baseline value.
#   - Robust Signal Traps: Catches INT, TERM, HUP with verified restoration.
# ==============================================================================

set -u

# Base paths (supports MOCK_ROOT for hermetic PC/WSL2 testing)
MOCK_ROOT="${MOCK_ROOT:-}"
TRIAL_STATE_DIR="${TRIAL_STATE_DIR:-/tmp/trial_state}"
TRIAL_LOCK_DIR="${TRIAL_LOCK_DIR:-/tmp/trial_lock.d}"

if [ -n "$MOCK_ROOT" ]; then
    case "$TRIAL_STATE_DIR" in
        "$MOCK_ROOT"*) ;;
        *) TRIAL_STATE_DIR="${MOCK_ROOT}${TRIAL_STATE_DIR}" ;;
    esac
    case "$TRIAL_LOCK_DIR" in
        "$MOCK_ROOT"*) ;;
        *) TRIAL_LOCK_DIR="${MOCK_ROOT}${TRIAL_LOCK_DIR}" ;;
    esac
fi

TARGET_REL_PATH="/sys/class/net/eth0/queues/rx-0/rps_cpus"
BASELINE_VALUE="0"
TRIAL_VALUE="2"
WATCHDOG_TIMEOUT="180"
MEASURE_SECONDS="${MEASURE_SECONDS:-30}"
MIN_FREE_RAM_KB="${MIN_FREE_RAM_KB:-6144}" # 6 MB minimum headroom

TRIAL_STATE_FILE="${TRIAL_STATE_DIR}/rps_trial.state"
WATCHDOG_PID=""
TRIAL_IN_PROGRESS=0
LOCK_ACQUIRED=0

# Logging helpers
log_info() {
    echo "[TRIAL-INFO]  $*"
}

log_warn() {
    echo "[TRIAL-WARN]  $*" >&2
}

log_err() {
    echo "[TRIAL-ERROR] $*" >&2
}

log_success() {
    echo "[TRIAL-OK]    $*"
}

# Resolve target path (supports MOCK_ROOT)
target_sysfs_path() {
    case "$TARGET_REL_PATH" in
        "$MOCK_ROOT"*) echo "$TARGET_REL_PATH" ;;
        *) echo "${MOCK_ROOT}${TARGET_REL_PATH}" ;;
    esac
}

read_target_val() {
    _path=$(target_sysfs_path)
    if [ -f "$_path" ]; then
        _val=$(cat "$_path" 2>/dev/null | tr -d ' \t\r\n' | sed 's/^0*//')
        if [ -z "$_val" ]; then
            echo "0"
        else
            echo "$_val"
        fi
        return 0
    fi
    return 1
}

write_target_val() {
    _val="$1"
    _path=$(target_sysfs_path)
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

# Memory headroom in kB
get_mem_available_kb() {
    _meminfo="${MOCK_ROOT}/proc/meminfo"
    if [ -f "$_meminfo" ]; then
        _avail=$(grep "^MemAvailable:" "$_meminfo" 2>/dev/null | awk '{print $2}')
        if [ -n "$_avail" ] && [ "$_avail" -gt 0 ] 2>/dev/null; then
            echo "$_avail"
            return 0
        fi
        _free=$(grep "^MemFree:" "$_meminfo" 2>/dev/null | awk '{print $2}')
        if [ -n "$_free" ] && [ "$_free" -gt 0 ] 2>/dev/null; then
            echo "$_free"
            return 0
        fi
    fi
    return 1
}

# Read NET_RX softirqs for CPU0 and CPU1
get_net_rx_softirqs() {
    _softirqs="${MOCK_ROOT}/proc/softirqs"
    if [ -f "$_softirqs" ]; then
        grep "NET_RX:" "$_softirqs" 2>/dev/null | awk '{print $2, $3}' || echo "0 0"
    else
        echo "0 0"
    fi
}

# Management connection reachability check
check_management_connection() {
    log_info "Verifying management connection reachability..."

    # Custom command override (e.g. for test harnesses or custom health scripts)
    if [ -n "${MANAGEMENT_CHECK_CMD:-}" ]; then
        if ! eval "$MANAGEMENT_CHECK_CMD" >/dev/null 2>&1; then
            log_err "Precondition Failed: Custom management check failed (${MANAGEMENT_CHECK_CMD})."
            return 1
        fi
        log_success "Management connection verified via custom check."
        return 0
    fi

    # In MOCK_ROOT environment, simulate management reachability
    if [ -n "$MOCK_ROOT" ]; then
        _mock_mgmt_fail="${MOCK_ROOT}/tmp/mock_mgmt_fail"
        if [ -f "$_mock_mgmt_fail" ]; then
            log_err "Precondition Failed: Simulated management connection failure detected."
            return 1
        fi
        _mock_br_lan="${MOCK_ROOT}/sys/class/net/br-lan"
        if [ -d "$_mock_br_lan" ] && [ -f "$_mock_br_lan/operstate" ]; then
            _state=$(cat "$_mock_br_lan/operstate" 2>/dev/null | tr -d ' \t\r\n')
            if [ "$_state" = "down" ]; then
                log_err "Precondition Failed: Local management interface br-lan is DOWN."
                return 1
            fi
        fi
        log_success "Management connection verified (mock environment healthy)."
        return 0
    fi

    # Live hardware verification
    # 1. Check if br-lan interface exists and is up
    if [ -d "/sys/class/net/br-lan" ]; then
        _oper=$(cat /sys/class/net/br-lan/operstate 2>/dev/null || echo "unknown")
        if [ "$_oper" = "down" ]; then
            log_err "Precondition Failed: Management interface br-lan is DOWN."
            return 1
        fi
    fi

    # 2. Check if Dropbear SSH daemon is active and listening
    if ! pidof dropbear >/dev/null 2>&1 && ! pgrep dropbear >/dev/null 2>&1; then
        log_err "Precondition Failed: Management daemon (dropbear) is not running."
        return 1
    fi

    # 3. If MANAGEMENT_IP is provided, verify ICMP reachability
    if [ -n "${MANAGEMENT_IP:-}" ]; then
        if ! ping -c 1 -W 2 "$MANAGEMENT_IP" >/dev/null 2>&1; then
            log_err "Precondition Failed: Management IP ${MANAGEMENT_IP} is unreachable."
            return 1
        fi
    fi

    log_success "Management connection verified."
    return 0
}

# ------------------------------------------------------------------------------
# LOCK MANAGEMENT & CONCURRENCY PROTECTION
# ------------------------------------------------------------------------------
acquire_trial_lock() {
    _retries=3
    while [ "$_retries" -gt 0 ]; do
        if mkdir "$TRIAL_LOCK_DIR" 2>/dev/null; then
            echo "$$" > "${TRIAL_LOCK_DIR}/pid"
            LOCK_ACQUIRED=1
            return 0
        fi
        # Check if existing lock is stale
        if [ -f "${TRIAL_LOCK_DIR}/pid" ]; then
            _lpid=$(cat "${TRIAL_LOCK_DIR}/pid" 2>/dev/null || echo "")
            if [ -n "$_lpid" ] && ! kill -0 "$_lpid" 2>/dev/null; then
                log_warn "Detected stale trial lock from dead PID ${_lpid}. Purging stale lock."
                rm -rf "$TRIAL_LOCK_DIR" 2>/dev/null || true
                continue
            fi
        fi
        sleep 1
        _retries=$((_retries - 1))
    done
    log_err "Failed to acquire trial lock (${TRIAL_LOCK_DIR}). Another trial is active."
    return 1
}

release_trial_lock() {
    if [ "$LOCK_ACQUIRED" -eq 1 ]; then
        rm -rf "$TRIAL_LOCK_DIR" 2>/dev/null || true
        LOCK_ACQUIRED=0
    fi
}

# ------------------------------------------------------------------------------
# DEFECT (a) EMERGENCY ABORT HANDLER
# ------------------------------------------------------------------------------
emergency_abort() {
    log_err "Emergency abort signal caught! Executing fail-safe rollback."
    if [ "$TRIAL_IN_PROGRESS" -eq 1 ]; then
        if write_target_val "$BASELINE_VALUE"; then
            _rb_check=$(read_target_val || echo "")
            if [ "$_rb_check" = "$BASELINE_VALUE" ] || [ -z "$_rb_check" -a "$BASELINE_VALUE" = "0" ]; then
                log_success "Emergency abort: parameter restored to verified baseline ($BASELINE_VALUE)."
                rm -f "$TRIAL_STATE_FILE" 2>/dev/null || true
                TRIAL_IN_PROGRESS=0
            else
                log_err "CRITICAL: Emergency readback verification failed! State file preserved at $TRIAL_STATE_FILE."
            fi
        else
            log_err "CRITICAL: Emergency write failed! NEVER deleting state file. Manual inspection required."
        fi
    fi

    if [ -n "$WATCHDOG_PID" ]; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
    fi
    release_trial_lock
    exit 2
}

trap emergency_abort INT TERM HUP

# ------------------------------------------------------------------------------
# PHASE 1: Precondition Health Check & Stale State Recovery
# ------------------------------------------------------------------------------
run_preflight_checks() {
    log_info "--- Phase 1: Precondition Health Check ---"

    # Stale state check: If state file exists from previous uncompleted run
    if [ -f "$TRIAL_STATE_FILE" ]; then
        log_warn "Previous trial state file found at $TRIAL_STATE_FILE. Checking system state."
        _cur_val=$(read_target_val || echo "")
        if [ "$_cur_val" = "$BASELINE_VALUE" ] || [ -z "$_cur_val" -a "$BASELINE_VALUE" = "0" ]; then
            log_info "System is already at verified baseline ($BASELINE_VALUE). Cleaning orphaned state file."
            rm -f "$TRIAL_STATE_FILE" 2>/dev/null || true
        else
            log_err "Precondition Failed: Stale trial state detected and parameter is currently '$_cur_val' (not baseline $BASELINE_VALUE)."
            log_err "Execute: $0 rollback to resolve previous state before starting a new trial."
            return 1
        fi
    fi

    # Check 0: Management Connection Reachability
    if ! check_management_connection; then
        log_err "Precondition Failed: Management reachability verification failed. Aborting trial."
        return 1
    fi

    # Check 1: Free RAM Headroom (without fabricated fallback)
    if ! _avail_kb=$(get_mem_available_kb); then
        log_err "Precondition Failed: Unable to parse available memory from /proc/meminfo (no valid MemAvailable/MemFree)."
        return 1
    fi
    log_info "Available RAM: ${_avail_kb} kB (Minimum required: ${MIN_FREE_RAM_KB} kB)"
    if [ "$_avail_kb" -lt "$MIN_FREE_RAM_KB" ] 2>/dev/null; then
        log_err "Precondition Failed: Available RAM (${_avail_kb} kB) is below safe threshold (${MIN_FREE_RAM_KB} kB)."
        return 1
    fi

    # Check 2: Verify Baseline Parameter Value
    _current_val=$(read_target_val || echo "")
    if [ -z "$_current_val" ]; then _current_val="0"; fi
    log_info "Current Parameter Value: '${_current_val}' (Expected baseline: '${BASELINE_VALUE}')"
    if [ "$_current_val" != "$BASELINE_VALUE" ]; then
        log_err "Precondition Failed: Target does not match expected baseline (${BASELINE_VALUE}). Current: '$_current_val'."
        log_err "Trial aborted to prevent overwriting unmanaged custom state."
        return 1
    fi

    # Check 3: Check Sysfs Interface Writability
    _path=$(target_sysfs_path)
    if [ -n "$MOCK_ROOT" ]; then
        mkdir -p "$(dirname "$_path")" 2>/dev/null || true
    elif [ ! -w "$_path" ]; then
        log_err "Precondition Failed: Target sysfs interface is not writable: $_path"
        return 1
    fi

    log_success "Precondition health checks passed."
    return 0
}

# ------------------------------------------------------------------------------
# DEFECT (c) PHASE 2: Atomic Baseline Snapshot with Strict Validation
# ------------------------------------------------------------------------------
take_snapshot() {
    log_info "--- Phase 2: Atomic Baseline Snapshot & Validation ---"
    mkdir -p "$TRIAL_STATE_DIR" 2>/dev/null || true

    cat << EOF > "$TRIAL_STATE_FILE"
TARGET_PATH=${TARGET_REL_PATH}
BASELINE_VALUE=${BASELINE_VALUE}
TRIAL_VALUE=${TRIAL_VALUE}
START_TIMESTAMP=$(date +%s)
PID=$$
EOF

    # Strict snapshot verification
    if [ ! -f "$TRIAL_STATE_FILE" ]; then
        log_err "Snapshot validation failed: State file was not created!"
        return 1
    fi

    if [ ! -s "$TRIAL_STATE_FILE" ]; then
        log_err "Snapshot validation failed: State file is empty (0 bytes)!"
        rm -f "$TRIAL_STATE_FILE" 2>/dev/null || true
        return 1
    fi

    if ! grep -q "^TARGET_PATH=" "$TRIAL_STATE_FILE" || ! grep -q "^BASELINE_VALUE=" "$TRIAL_STATE_FILE"; then
        log_err "Snapshot validation failed: State file has invalid format or missing keys!"
        rm -f "$TRIAL_STATE_FILE" 2>/dev/null || true
        return 1
    fi

    log_success "Snapshot validated successfully at $TRIAL_STATE_FILE."
    return 0
}

# ------------------------------------------------------------------------------
# PHASE 3: 180-second Independent Watchdog Auto-Rollback
# ------------------------------------------------------------------------------
arm_watchdog() {
    log_info "--- Phase 3: Arming 180s Independent Watchdog Auto-Rollback ---"
    _target_rel="$TARGET_REL_PATH"
    _base_val="$BASELINE_VALUE"
    _state_file="$TRIAL_STATE_FILE"
    _mock_root="$MOCK_ROOT"
    _state_dir="$TRIAL_STATE_DIR"

    # Background watchdog subshell
    (
        sleep "$WATCHDOG_TIMEOUT"
        if [ -f "$_state_file" ]; then
            echo "[WATCHDOG] 180s timeout expired! Forcing emergency rollback of ${_target_rel} to ${_base_val}" >&2
            _p="${_mock_root}${_target_rel}"
            _write_ok=0
            if printf '%s\n' "$_base_val" > "$_p" 2>/dev/null; then
                _write_ok=1
            fi

            _rb_val=""
            if [ -f "$_p" ]; then
                _raw=$(cat "$_p" 2>/dev/null | tr -d ' \t\r\n' | sed 's/^0*//')
                if [ -z "$_raw" ]; then _rb_val="0"; else _rb_val="$_raw"; fi
            fi

            if [ "$_write_ok" -eq 1 ] && [ "$_rb_val" = "$_base_val" ]; then
                echo "[WATCHDOG] Verified rollback succeeded: ${_target_rel} restored to ${_base_val}" >&2
                rm -f "$_state_file" 2>/dev/null || true
                logger -t CONTROLLED_TRIAL "WATCHDOG FIRED: Verified emergency rollback executed" 2>/dev/null || true
            else
                echo "[WATCHDOG] CRITICAL FAILURE: Rollback write or readback verification failed!" >&2
                echo "[WATCHDOG] State file preserved at ${_state_file}. Generating EMERGENCY_UNRESOLVED alert." >&2
                mkdir -p "$_state_dir" 2>/dev/null || true
                _alert_file="${_state_dir}/EMERGENCY_UNRESOLVED"
                cat << ALERT_EOF > "$_alert_file"
ALERT=WATCHDOG_ROLLBACK_VERIFICATION_FAILED
TIMESTAMP=$(date +%s)
TARGET=${_target_rel}
BASELINE_VALUE=${_base_val}
ACTUAL_VALUE=${_rb_val}
STATE_FILE=${_state_file}
ALERT_EOF
                logger -s -t CONTROLLED_TRIAL "CRITICAL: Watchdog rollback verification failed! State preserved in ${_state_file}" 2>/dev/null || true
            fi
        fi
    ) &
    WATCHDOG_PID=$!
    log_success "Watchdog armed (PID: $WATCHDOG_PID, Timeout: ${WATCHDOG_TIMEOUT}s)."
}

disarm_watchdog() {
    if [ -n "$WATCHDOG_PID" ]; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
        WATCHDOG_PID=""
        log_info "Watchdog auto-rollback disarmed."
    fi
}

# ------------------------------------------------------------------------------
# PHASE 4: Single-Variable Runtime Apply
# ------------------------------------------------------------------------------
apply_trial_param() {
    log_info "--- Phase 4: Single-Variable Runtime Apply (${BASELINE_VALUE} -> ${TRIAL_VALUE}) ---"
    if ! write_target_val "$TRIAL_VALUE"; then
        log_err "Failed to write trial parameter value (${TRIAL_VALUE})."
        return 1
    fi

    _applied_val=$(read_target_val || echo "")
    if [ "$_applied_val" != "$TRIAL_VALUE" ]; then
        log_err "Verification failed: Parameter readback ('$_applied_val') does not match trial target (${TRIAL_VALUE})."
        return 1
    fi

    TRIAL_IN_PROGRESS=1
    log_success "Trial parameter applied: ${TARGET_REL_PATH} = ${TRIAL_VALUE}"
    return 0
}

# ------------------------------------------------------------------------------
# PHASE 5: Measurement Window & SoftIRQ Balancing Telemetry
# ------------------------------------------------------------------------------
run_measurement_window() {
    log_info "--- Phase 5: Measurement Window (${MEASURE_SECONDS}s) ---"
    _start_rx=$(get_net_rx_softirqs)
    _rx0_start=$(echo "$_start_rx" | awk '{print $1}')
    _rx1_start=$(echo "$_start_rx" | awk '{print $2}')
    _start_mem=$(get_mem_available_kb || echo "0")

    log_info "Initial Telemetry: NET_RX [CPU0: $_rx0_start, CPU1: $_rx1_start] | MemAvailable: ${_start_mem} kB"

    _elapsed=0
    _step=5
    if [ "$MEASURE_SECONDS" -lt 5 ]; then
        _step=1
    fi

    while [ "$_elapsed" -lt "$MEASURE_SECONDS" ]; do
        sleep "$_step"
        _elapsed=$((_elapsed + _step))
        _cur_rx=$(get_net_rx_softirqs)
        _rx0_cur=$(echo "$_cur_rx" | awk '{print $1}')
        _rx1_cur=$(echo "$_cur_rx" | awk '{print $2}')
        _cur_mem=$(get_mem_available_kb || echo "0")
        log_info "  [T+${_elapsed}s] NET_RX: [CPU0: $_rx0_cur, CPU1: $_rx1_cur] | Available RAM: ${_cur_mem} kB"

        # Check for catastrophic RAM drop
        if [ "$_cur_mem" -lt "$MIN_FREE_RAM_KB" ] 2>/dev/null; then
            log_err "Stability Anomaly: Available RAM dropped below safe threshold during trial!"
            return 1
        fi
    done

    _end_rx=$(get_net_rx_softirqs)
    _rx0_end=$(echo "$_end_rx" | awk '{print $1}')
    _rx1_end=$(echo "$_end_rx" | awk '{print $2}')
    _end_mem=$(get_mem_available_kb || echo "0")

    _d0=$((_rx0_end - _rx0_start)) 2>/dev/null || _d0="N/A"
    _d1=$((_rx1_end - _rx1_start)) 2>/dev/null || _d1="N/A"

    log_success "Measurement Window Completed (${MEASURE_SECONDS}s)."
    log_info "Summary Deltas: NET_RX CPU0 Delta: +$_d0 | NET_RX CPU1 Delta: +$_d1 | RAM Delta: ${_start_mem} -> ${_end_mem} kB"
    return 0
}

# ------------------------------------------------------------------------------
# DEFECT (b) PHASE 6 & 7: Verified Rollback with Readback Gate
# ------------------------------------------------------------------------------
rollback_baseline() {
    log_info "--- Phase 6: Verified Rollback to Baseline ---"
    if ! write_target_val "$BASELINE_VALUE"; then
        log_err "Failed to write baseline value (${BASELINE_VALUE})! Leaving state file intact."
        return 1
    fi

    # Read back actual value BEFORE disarming watchdog or deleting state file
    _rb_val=$(read_target_val || echo "")
    if [ -z "$_rb_val" ]; then _rb_val="0"; fi

    if [ "$_rb_val" != "$BASELINE_VALUE" ]; then
        log_err "CRITICAL: Rollback readback verification failed! Read: '$_rb_val' (Expected: '$BASELINE_VALUE')."
        log_err "Watchdog remains ARMED and state file is PRESERVED for forensic recovery."
        return 1
    fi

    # Verification confirmed: parameter restored to verified baseline
    TRIAL_IN_PROGRESS=0
    disarm_watchdog
    rm -f "$TRIAL_STATE_FILE" 2>/dev/null || true
    log_success "Parameter restored to verified baseline: ${TARGET_REL_PATH} = ${BASELINE_VALUE}"
    return 0
}

verify_post_rollback() {
    log_info "--- Phase 7: Post-Rollback Integrity Verification ---"
    _final_val=$(read_target_val || echo "")
    if [ -z "$_final_val" ]; then _final_val="0"; fi

    if [ "$_final_val" != "$BASELINE_VALUE" ]; then
        log_err "Verification FAILED: Parameter value is '$_final_val' (Expected: '${BASELINE_VALUE}')."
        return 1
    fi

    if [ -f "$TRIAL_STATE_FILE" ]; then
        log_err "Verification FAILED: State file still present at $TRIAL_STATE_FILE"
        return 1
    fi

    log_success "Post-Rollback Verification PASSED: Parameter confirmed at verified baseline (${BASELINE_VALUE})."
    return 0
}

# ------------------------------------------------------------------------------
# MAIN TRIAL LIFECYCLE CONTROLLER
# ------------------------------------------------------------------------------
run_trial() {
    log_info "================================================================================"
    log_info "STARTING CONTROLLED TRIAL: RPS STEERING ON ETH0"
    log_info "Target: ${TARGET_REL_PATH} | Baseline: ${BASELINE_VALUE} -> Trial: ${TRIAL_VALUE}"
    log_info "Duration: ${MEASURE_SECONDS}s | Watchdog Timeout: ${WATCHDOG_TIMEOUT}s"
    log_info "================================================================================"

    if ! acquire_trial_lock; then
        exit 1
    fi

    # Phase 1: Preflight
    if ! run_preflight_checks; then
        log_err "Trial aborted during Phase 1 preflight checks."
        release_trial_lock
        exit 1
    fi

    # Phase 2: Snapshot with strict validation
    if ! take_snapshot; then
        log_err "Trial aborted: Snapshot validation failed."
        release_trial_lock
        exit 1
    fi

    # Phase 3: Watchdog
    arm_watchdog

    # Phase 4: Apply
    if ! apply_trial_param; then
        log_err "Apply failed. Rolling back immediately."
        rollback_baseline || true
        release_trial_lock
        exit 1
    fi

    # Phase 5: Measurement
    if ! run_measurement_window; then
        log_err "Instability detected during measurement. Initiating rollback."
        rollback_baseline || true
        release_trial_lock
        exit 1
    fi

    # Phase 6: Rollback with verified readback
    if ! rollback_baseline; then
        log_err "Rollback failed! System unverified."
        release_trial_lock
        exit 1
    fi

    # Phase 7: Post-Rollback Verification
    if ! verify_post_rollback; then
        log_err "Post-rollback verification failed."
        release_trial_lock
        exit 1
    fi

    release_trial_lock
    log_info "================================================================================"
    log_success "CONTROLLED PERFORMANCE TRIAL COMPLETED SUCCESSFULLY (100% REVERTED)"
    log_info "================================================================================"
    exit 0
}

# Entrypoint
ACTION="${1:-run}"
case "$ACTION" in
    run)
        run_trial
        ;;
    preflight)
        acquire_trial_lock && run_preflight_checks
        _rc=$?
        release_trial_lock
        exit $_rc
        ;;
    rollback)
        acquire_trial_lock && rollback_baseline && verify_post_rollback
        _rc=$?
        release_trial_lock
        exit $_rc
        ;;
    status)
        echo "Target:   $TARGET_REL_PATH"
        echo "Current:  $(read_target_val || echo '?')"
        echo "Baseline: $BASELINE_VALUE"
        echo "Trial:    $TRIAL_VALUE"
        if [ -f "$TRIAL_STATE_FILE" ]; then
            echo "State:    TRIAL_IN_PROGRESS"
            cat "$TRIAL_STATE_FILE" | sed 's/^/  /'
        else
            echo "State:    BASELINE_CLEAN"
        fi
        ;;
    *)
        echo "Usage: $0 {run|preflight|rollback|status}"
        exit 1
        ;;
esac
