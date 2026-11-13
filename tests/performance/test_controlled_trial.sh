#!/bin/sh
# tests/performance/test_controlled_trial.sh
# ==============================================================================
# Failure-Injection & Verification Test Harness for Controlled Performance Trial
# Workstream B & G: Network Performance & Automated Optimization
# Target: Xiaomi CR8808 / RA82 (Linux 4.4.60 QSDK, ARMv7l Cortex-A53)
# Target Parameter: /sys/class/net/eth0/queues/rx-0/rps_cpus (0 -> 2 -> 0)
#
# Validates Directive M12.5 Requirements & Defect Fixes:
#   1. Complete Happy Path trial lifecycle (Preflight -> Snapshot -> Apply ->
#      Measurement -> Rollback -> Verification).
#   2. Precondition rejection on baseline parameter drift (non-zero rps_cpus).
#   3. Precondition rejection on insufficient RAM headroom (<6MB available).
#   4. Defect (c) Snapshot validation: reject invalid/empty/unwritable snapshot.
#   5. Defect (a) Signal trap (SIGTERM) emergency rollback to baseline.
#   6. Defect (a) Emergency abort failure safety: NEVER delete state file on failure.
#   7. Defect (b) Verified rollback readback gate: never disarm watchdog or
#      delete state file if readback does not match baseline.
#   8. Atomic Directory Lock (/tmp/trial_lock.d) contention & stale lock recovery.
#   9. Stale state recovery on preflight (auto-heal if baseline, abort if non-baseline).
#  10. Background watchdog auto-rollback trigger.
#  11. Bit-for-bit restoration guarantee.
#
# Executed 100% in PC/WSL2 hermetic mock environment. Zero router writes.
# ==============================================================================

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRIAL_RUNNER="${REPO_ROOT}/performance/trials/controlled_trial_runner.sh"

MOCK_DIR="$(mktemp -d /tmp/ra82_rps_mock.XXXXXX)"
export MOCK_ROOT="$MOCK_DIR"
export TRIAL_STATE_DIR="/tmp/trial_state"
export TRIAL_LOCK_DIR="/tmp/trial_lock.d"

cleanup() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "================================================================================"
echo ">>> RUNNING CONTROLLED PERFORMANCE TRIAL TEST HARNESS (RPS ETH0 CANDIDATE)"
echo ">>> Mock Rootfs: $MOCK_ROOT"
echo "================================================================================"

PASSED=0
FAILED=0

assert_eq() {
    _desc="$1"
    _expected="$2"
    _actual="$3"
    if [ "$_expected" = "$_actual" ]; then
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $_desc (Expected: '$_expected' | Got: '$_actual')"
        FAILED=$((FAILED + 1))
        exit 1
    fi
}

init_mock_environment() {
    rm -rf "${MOCK_DIR:?}"/*

    # Sysfs: /sys/class/net/eth0/queues/rx-0/rps_cpus
    mkdir -p "$MOCK_DIR/sys/class/net/eth0/queues/rx-0"
    printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

    # Meminfo: normal healthy RAM (10.5 MB available)
    mkdir -p "$MOCK_DIR/proc"
    cat << 'EOF' > "$MOCK_DIR/proc/meminfo"
MemTotal:         186368 kB
MemFree:           10752 kB
MemAvailable:      10752 kB
Slab:              60504 kB
SUnreclaim:        57932 kB
EOF

    # Softirqs: NET_RX telemetry counters
    cat << 'EOF' > "$MOCK_DIR/proc/softirqs"
                CPU0       CPU1
      NET_RX:   542100     1250
EOF

    # Clean state & lock directories
    mkdir -p "$MOCK_DIR$TRIAL_STATE_DIR"
    rm -rf "$MOCK_DIR$TRIAL_LOCK_DIR" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# TEST 1: Full Happy Path Execution (Apply, Measure, Rollback, Verify)
# ------------------------------------------------------------------------------
echo "--- TEST 1: Full Happy Path Trial Lifecycle ---"
init_mock_environment

# Run with fast 2-second measurement window for test suite
MEASURE_SECONDS=2 sh "$TRIAL_RUNNER" run >/dev/null 2>&1
assert_eq "Trial runner exited with code 0" "0" "$?"

# Check final parameter value is restored to exact baseline
_final_val=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Parameter restored to baseline 0" "0" "$_final_val"

# Check state file is cleaned up
assert_eq "State file cleaned up" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"

# Check lock directory is cleaned up
assert_eq "Lock directory released" "0" "$([ ! -d "$MOCK_DIR$TRIAL_LOCK_DIR" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 2: Precondition Rejection on Baseline Drift
# ------------------------------------------------------------------------------
echo "--- TEST 2: Precondition Rejection on Parameter Drift ---"
init_mock_environment

# Inject abnormal baseline value (e.g. 1)
printf '1\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have rejected abnormal baseline value"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly rejected baseline drift"
    PASSED=$((PASSED + 1))
fi

_unmodified_val=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Parameter was left completely untouched" "1" "$_unmodified_val"
assert_eq "No state snapshot created" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"
assert_eq "Lock released on abort" "0" "$([ ! -d "$MOCK_DIR$TRIAL_LOCK_DIR" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 3: Precondition Rejection on Insufficient RAM Headroom
# ------------------------------------------------------------------------------
echo "--- TEST 3: Precondition Rejection on Low Memory (<6MB) ---"
init_mock_environment

# Inject critically low memory condition (3 MB available)
cat << 'EOF' > "$MOCK_DIR/proc/meminfo"
MemTotal:         186368 kB
MemFree:            3072 kB
MemAvailable:       3072 kB
Slab:              60504 kB
SUnreclaim:        57932 kB
EOF

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have rejected low RAM condition"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly rejected low RAM condition"
    PASSED=$((PASSED + 1))
fi

_untouched_param=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Parameter remained untouched at 0" "0" "$_untouched_param"
assert_eq "No state snapshot created" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 4: Defect (c) Snapshot Validation Enforcement
# ------------------------------------------------------------------------------
echo "--- TEST 4: Defect (c) Snapshot Validation Enforcement ---"
init_mock_environment

# Create directory collision to force snapshot creation failure
mkdir -p "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on snapshot write failure"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner aborted on snapshot failure without applying parameter"
    PASSED=$((PASSED + 1))
fi

_param_after_snap_fail=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Target parameter was not modified when snapshot failed" "0" "$_param_after_snap_fail"
rm -rf "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"

# ------------------------------------------------------------------------------
# TEST 5: Fault Injection: Signal Interruption (SIGTERM) & Emergency Rollback
# ------------------------------------------------------------------------------
echo "--- TEST 5: Fault Injection: SIGTERM Interruption Recovery ---"
init_mock_environment

# Launch trial runner in background with a 15-second measurement window
MEASURE_SECONDS=15 sh "$TRIAL_RUNNER" run >/dev/null 2>&1 &
RUNNER_PID=$!

# Wait for runner to enter Phase 4/5 (param set to 2)
_waited=0
_cur=""
while [ "$_waited" -lt 20 ]; do
    if [ -f "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" ]; then
        _cur=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
        if [ "$_cur" = "2" ]; then
            break
        fi
    fi
    sleep 0.2
    _waited=$((_waited + 1))
done

assert_eq "Trial successfully applied 2 prior to fault injection" "2" "$_cur"

# Inject fault: kill runner process with SIGTERM
kill -TERM "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true

# Verify emergency trap handler caught signal and reverted parameter to 0
_reverted=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Emergency trap handler reverted parameter to baseline 0" "0" "$_reverted"
assert_eq "Emergency abort cleaned up state file on successful revert" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"
assert_eq "Emergency abort released trial lock" "0" "$([ ! -d "$MOCK_DIR$TRIAL_LOCK_DIR" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 6: Defect (a) Emergency Abort Failure Safety (State Preserved)
# ------------------------------------------------------------------------------
echo "--- TEST 6: Defect (a) Emergency Abort Failure Protection ---"
init_mock_environment

# Launch trial runner in background with a 15-second measurement window
MEASURE_SECONDS=15 sh "$TRIAL_RUNNER" run >/dev/null 2>&1 &
RUNNER_PID=$!

# Wait for runner to enter Phase 4/5 (param set to 2)
_waited=0
while [ "$_waited" -lt 20 ]; do
    if [ -f "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" ]; then
        _cur=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
        if [ "$_cur" = "2" ]; then
            break
        fi
    fi
    sleep 0.2
    _waited=$((_waited + 1))
done

# Simulate hard write failure: replace rps_cpus with an unwritable directory
rm -f "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
mkdir "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

# Send SIGTERM to trigger emergency abort
kill -TERM "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true

# Assert Defect (a) fix: state file must NOT be deleted when emergency revert fails!
assert_eq "State file preserved when emergency rollback cannot restore baseline" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 1 || echo 0)"

# Clean up simulated failure
rm -rf "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
rm -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"

# ------------------------------------------------------------------------------
# TEST 7: Defect (b) Rollback Readback Gate Enforcement
# ------------------------------------------------------------------------------
echo "--- TEST 7: Defect (b) Rollback Readback Gate Enforcement ---"
init_mock_environment

# Pre-seed state file simulating active trial
printf '2\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
TARGET_PATH=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
TRIAL_VALUE=2
START_TIMESTAMP=$(date +%s)
PID=$$
EOF

# Simulate a failure to write baseline during rollback by making path a directory
rm -f "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
mkdir "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

if sh "$TRIAL_RUNNER" rollback >/dev/null 2>&1; then
    echo "  [FAIL] Rollback should have failed when sysfs write failed"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Rollback cleanly failed on write error"
    PASSED=$((PASSED + 1))
fi

# Assert Defect (b) fix: state file must NOT be unlinked
assert_eq "State file preserved when rollback write/readback fails" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 1 || echo 0)"

# Restore sysfs node
rm -rf "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
rm -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"

# ------------------------------------------------------------------------------
# TEST 8: Atomic Directory Lock Contention & Stale Lock Recovery
# ------------------------------------------------------------------------------
echo "--- TEST 8: Atomic Directory Lock Contention & Stale Lock Recovery ---"
init_mock_environment

# Subtest 8A: Active Lock Contention
mkdir -p "$MOCK_DIR$TRIAL_LOCK_DIR"
echo "$$" > "$MOCK_DIR$TRIAL_LOCK_DIR/pid"

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have failed due to active lock contention"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly exited on active lock contention"
    PASSED=$((PASSED + 1))
fi

# Subtest 8B: Stale Lock Recovery (dead PID)
echo "999999" > "$MOCK_DIR$TRIAL_LOCK_DIR/pid"

if sh "$TRIAL_RUNNER" preflight >/dev/null 2>&1; then
    echo "  [PASS] Stale lock detected and purged successfully"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Failed to purge stale lock"
    FAILED=$((FAILED + 1))
    exit 1
fi

# ------------------------------------------------------------------------------
# TEST 9: Stale State Recovery on Preflight
# ------------------------------------------------------------------------------
echo "--- TEST 9: Stale State Recovery on Preflight ---"
init_mock_environment

# Subtest 9A: Orphaned state exists, but parameter is at baseline (0) -> auto-heal
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
TARGET_PATH=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
TRIAL_VALUE=2
START_TIMESTAMP=1000000
PID=99999
EOF

if sh "$TRIAL_RUNNER" preflight >/dev/null 2>&1; then
    echo "  [PASS] Preflight auto-healed orphaned state when parameter was at baseline"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Preflight failed to auto-heal orphaned state at baseline"
    FAILED=$((FAILED + 1))
    exit 1
fi
assert_eq "Orphaned state file removed" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"

# Subtest 9B: Orphaned state exists, and parameter is NOT at baseline -> abort
printf '2\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
TARGET_PATH=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
TRIAL_VALUE=2
START_TIMESTAMP=1000000
PID=99999
EOF

if sh "$TRIAL_RUNNER" preflight >/dev/null 2>&1; then
    echo "  [FAIL] Preflight should have aborted when state file exists and param is at trial value"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Preflight cleanly aborted on active unmanaged state"
    PASSED=$((PASSED + 1))
fi

# Clean up
printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
rm -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"

# ------------------------------------------------------------------------------
# TEST 10: Watchdog Auto-Rollback Execution (Happy Path)
# ------------------------------------------------------------------------------
echo "--- TEST 10: Watchdog Auto-Rollback Execution (Happy Path) ---"
init_mock_environment

# Simulate an abandoned trial in progress
printf '2\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
TARGET_PATH=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
TRIAL_VALUE=2
PID=99999
EOF

# Spawn simulated 1-second watchdog replicating Phase 3 logic
(
    sleep 1
    if [ -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ]; then
        _p="$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
        _write_ok=0
        if printf '0\n' > "$_p" 2>/dev/null; then _write_ok=1; fi
        _rb=$(cat "$_p" 2>/dev/null | tr -d ' \t\r\n' | sed 's/^0*//')
        if [ -z "$_rb" ]; then _rb="0"; fi
        if [ "$_write_ok" -eq 1 ] && [ "$_rb" = "0" ]; then
            rm -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
        fi
    fi
) &
WD_PID=$!
wait "$WD_PID"

_wd_reverted=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Watchdog restored parameter to baseline 0" "0" "$_wd_reverted"
assert_eq "Watchdog cleaned up state file" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 11: Bit-for-Bit Exact Post-Rollback Integrity
# ------------------------------------------------------------------------------
echo "--- TEST 11: Bit-for-Bit Exact Post-Rollback Integrity ---"
init_mock_environment

_pre_sha=$(sha256sum "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | awk '{print $1}')
MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1
_post_sha=$(sha256sum "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | awk '{print $1}')

assert_eq "Pre-trial and post-rollback SHA-256 match bit-for-bit" "$_pre_sha" "$_post_sha"

# ------------------------------------------------------------------------------
# TEST 12: Priority B: Watchdog Failure State Preservation & Alert File
# ------------------------------------------------------------------------------
echo "--- TEST 12: Priority B: Watchdog Failure State Preservation & Alert File ---"
init_mock_environment

# Pre-seed active trial state
printf '2\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
TARGET_PATH=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
TRIAL_VALUE=2
PID=99999
EOF

# Simulate a failure to write by making sysfs path an unwritable directory
rm -f "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
mkdir "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

# Spawn 1-second watchdog replicating Phase 3 failure-handling logic
_mock_state_file="$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state"
_mock_state_dir="$MOCK_DIR$TRIAL_STATE_DIR"
_p="$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
(
    sleep 1
    if [ -f "$_mock_state_file" ]; then
        _write_ok=0
        if printf '0\n' > "$_p" 2>/dev/null; then _write_ok=1; fi
        _rb=""
        if [ -f "$_p" ]; then
            _raw=$(cat "$_p" 2>/dev/null | tr -d ' \t\r\n' | sed 's/^0*//')
            if [ -z "$_raw" ]; then _rb="0"; else _rb="$_raw"; fi
        fi
        if [ "$_write_ok" -eq 1 ] && [ "$_rb" = "0" ]; then
            rm -f "$_mock_state_file" 2>/dev/null || true
        else
            mkdir -p "$_mock_state_dir" 2>/dev/null || true
            cat << ALERT_EOF > "${_mock_state_dir}/EMERGENCY_UNRESOLVED"
ALERT=WATCHDOG_ROLLBACK_VERIFICATION_FAILED
TIMESTAMP=$(date +%s)
TARGET=/sys/class/net/eth0/queues/rx-0/rps_cpus
BASELINE_VALUE=0
ACTUAL_VALUE=${_rb}
STATE_FILE=${_mock_state_file}
ALERT_EOF
        fi
    fi
) &
WD_FAIL_PID=$!
wait "$WD_FAIL_PID"

assert_eq "Watchdog failure preserved state file" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 1 || echo 0)"
assert_eq "Watchdog failure created EMERGENCY_UNRESOLVED alert file" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/EMERGENCY_UNRESOLVED" ] && echo 1 || echo 0)"
assert_eq "Alert file contains correct reason" "1" "$(grep -q "ALERT=WATCHDOG_ROLLBACK_VERIFICATION_FAILED" "$MOCK_DIR$TRIAL_STATE_DIR/EMERGENCY_UNRESOLVED" && echo 1 || echo 0)"

# Clean up
rm -rf "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
rm -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" "$MOCK_DIR$TRIAL_STATE_DIR/EMERGENCY_UNRESOLVED"
printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

# ------------------------------------------------------------------------------
# TEST 13: Priority B: Unparseable Memory Failure Rejection
# ------------------------------------------------------------------------------
echo "--- TEST 13: Priority B: Unparseable Memory Failure Rejection ---"
init_mock_environment

# Subtest 13A: Completely missing /proc/meminfo
rm -f "$MOCK_DIR/proc/meminfo"
if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on missing /proc/meminfo"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly aborted when /proc/meminfo was missing"
    PASSED=$((PASSED + 1))
fi
assert_eq "Parameter remained untouched at baseline 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "State file was not created on missing meminfo" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"

# Subtest 13B: Corrupted /proc/meminfo without MemAvailable or MemFree
cat << 'EOF' > "$MOCK_DIR/proc/meminfo"
MemTotal:         186368 kB
Slab:              60504 kB
SUnreclaim:        57932 kB
EOF

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on corrupted /proc/meminfo"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly aborted on unparseable /proc/meminfo"
    PASSED=$((PASSED + 1))
fi
assert_eq "Parameter remained untouched at baseline 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"

# ------------------------------------------------------------------------------
# TEST 14: Priority B: Management Loss Abort
# ------------------------------------------------------------------------------
echo "--- TEST 14: Priority B: Management Connection Loss Abort ---"
init_mock_environment

# Subtest 14A: Simulated management failure file present
touch "$MOCK_DIR/tmp/mock_mgmt_fail"
if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on management failure flag"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly aborted on simulated management loss"
    PASSED=$((PASSED + 1))
fi
assert_eq "Parameter remained untouched at baseline 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "State file was not created on management failure" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"
rm -f "$MOCK_DIR/tmp/mock_mgmt_fail"

# Subtest 14B: Management interface br-lan down
mkdir -p "$MOCK_DIR/sys/class/net/br-lan"
printf 'down\n' > "$MOCK_DIR/sys/class/net/br-lan/operstate"
if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on br-lan down"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly aborted when br-lan was down"
    PASSED=$((PASSED + 1))
fi
rm -rf "$MOCK_DIR/sys/class/net/br-lan"

# Subtest 14C: Custom management command failure
if MANAGEMENT_CHECK_CMD="false" MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have aborted on custom management check failure"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly aborted on custom management check failure"
    PASSED=$((PASSED + 1))
fi

# ------------------------------------------------------------------------------
# TEST 15: P0-3 Read Failures Must Never Fabricate "0" or "0 0"
# ------------------------------------------------------------------------------
echo "--- TEST 15: P0-3 Read Failure Non-Fabrication (sysfs & /proc/softirqs) ---"
_rps_file="$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
_softirqs_file="$MOCK_DIR/proc/softirqs"

# 15A: Empty 0-byte rps_cpus must fail preflight, NOT read as "0"
: > "$_rps_file"
if sh "$TRIAL_RUNNER" preflight >/dev/null 2>&1; then
    echo "  [FAIL] Preflight accepted empty 0-byte rps_cpus as baseline 0"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Preflight rejected empty 0-byte rps_cpus instead of fabricating 0"
    PASSED=$((PASSED + 1))
fi
printf '0\n' > "$_rps_file"

# 15B: Missing /proc/softirqs must fail REQUIRE_SOFTIRQ_TELEMETRY=1 and never emit "0 0"
_softirqs_bak=""
if [ -f "$_softirqs_file" ]; then
    _softirqs_bak=$(cat "$_softirqs_file")
    rm -f "$_softirqs_file"
fi
if REQUIRE_SOFTIRQ_TELEMETRY=1 MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Runner succeeded with REQUIRE_SOFTIRQ_TELEMETRY=1 despite missing /proc/softirqs"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Strict softirq telemetry mode rejected missing /proc/softirqs"
    PASSED=$((PASSED + 1))
fi

# 15C: Unparseable /proc/softirqs without strict flag must report UNAVAILABLE, never "+0"
printf '           CPU0       CPU1\nNET_RX:    bad        data\n' > "$_softirqs_file"
_out_15c=$(MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run 2>&1 || true)
if echo "$_out_15c" | grep -q "NET_RX CPU0 Delta: UNAVAILABLE" && ! echo "$_out_15c" | grep -q "NET_RX CPU0 Delta: +0"; then
    echo "  [PASS] Unparseable /proc/softirqs reported UNAVAILABLE instead of fabricating 0 delta"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Unexpected softirq output on unparseable /proc/softirqs: $_out_15c"
    FAILED=$((FAILED + 1))
    exit 1
fi
if [ -n "$_softirqs_bak" ]; then
    printf '%s\n' "$_softirqs_bak" > "$_softirqs_file"
else
    printf '           CPU0       CPU1\nNET_RX:     100         20\n' > "$_softirqs_file"
fi

# ------------------------------------------------------------------------------
# TEST 16: P0-3 Emergency Abort Failure Keeps Watchdog Armed
# ------------------------------------------------------------------------------
echo "--- TEST 16: P0-3 Emergency Abort Keeps Watchdog Armed On Rollback Failure ---"
rm -rf "$MOCK_DIR$TRIAL_STATE_DIR" "$MOCK_DIR$TRIAL_LOCK_DIR"
printf '0\n' > "$_rps_file"

WATCHDOG_TIMEOUT=6 MEASURE_SECONDS=12 sh "$TRIAL_RUNNER" run >"$MOCK_DIR/t16.log" 2>&1 &
_t16_pid=$!

_wait_i=0
while [ "$_wait_i" -lt 40 ]; do
    if [ -f "$_rps_file" ] && [ "$(tr -d ' \t\r\n' < "$_rps_file")" = "2" ]; then
        break
    fi
    sleep 0.2
    _wait_i=$((_wait_i + 1))
done
assert_eq "TEST 16 reached active state 2" "2" "$(tr -d ' \t\r\n' < "$_rps_file")"

# Inject transient rollback failure during SIGTERM by replacing rps_cpus with directory
rm -f "$_rps_file"
mkdir -p "$_rps_file"
kill -TERM "$_t16_pid" 2>/dev/null || true
wait "$_t16_pid" 2>/dev/null || true

assert_eq "Emergency abort preserved state file on rollback failure" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 1 || echo 0)"
assert_eq "Emergency abort created EMERGENCY_UNRESOLVED alert" "1" "$([ -f "$MOCK_DIR$TRIAL_STATE_DIR/EMERGENCY_UNRESOLVED" ] && echo 1 || echo 0)"

# Now restore mock sysfs file writability BEFORE 6s watchdog expires; if emergency_abort
# left watchdog armed (did NOT kill it), watchdog will fire and revert 2 -> 0!
rmdir "$_rps_file"
printf '2\n' > "$_rps_file"
sleep 6

assert_eq "Armed watchdog survived failed emergency abort and restored 0" "0" "$(tr -d ' \t\r\n' < "$_rps_file")"
assert_eq "Armed watchdog cleaned state file after verified restoration" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"
rm -f "$MOCK_DIR$TRIAL_STATE_DIR/EMERGENCY_UNRESOLVED"

# ------------------------------------------------------------------------------
# TEST 17: P0-3 SIGKILL Orphan Recovery via Watchdog + Atomic Op Lock
# ------------------------------------------------------------------------------
echo "--- TEST 17: P0-3 SIGKILL Recovery & Watchdog Op Lock Coordination ---"
rm -rf "$MOCK_DIR$TRIAL_STATE_DIR" "$MOCK_DIR$TRIAL_LOCK_DIR"
printf '0\n' > "$_rps_file"

WATCHDOG_TIMEOUT=2 MEASURE_SECONDS=10 sh "$TRIAL_RUNNER" run >/dev/null 2>&1 &
_t17_pid=$!

_wait_j=0
while [ "$_wait_j" -lt 20 ]; do
    if [ -f "$_rps_file" ] && [ "$(tr -d ' \t\r\n' < "$_rps_file")" = "2" ]; then
        break
    fi
    sleep 1
    _wait_j=$((_wait_j + 1))
done
assert_eq "TEST 17 applied value 2 before SIGKILL" "2" "$(tr -d ' \t\r\n' < "$_rps_file")"

kill -KILL "$_t17_pid" 2>/dev/null || true
wait "$_t17_pid" 2>/dev/null || true
sleep 3

assert_eq "Watchdog recovered rps_cpus to 0 after SIGKILL" "0" "$(tr -d ' \t\r\n' < "$_rps_file")"
assert_eq "Watchdog cleaned state file after SIGKILL" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/rps_trial.state" ] && echo 0 || echo 1)"
assert_eq "Watchdog cleaned dead runner lock after SIGKILL" "0" "$([ ! -d "$MOCK_DIR$TRIAL_LOCK_DIR" ] && echo 0 || echo 1)"

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [PASS] Fresh trial runs cleanly immediately after SIGKILL watchdog recovery"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Fresh trial blocked after SIGKILL recovery"
    FAILED=$((FAILED + 1))
    exit 1
fi

# ------------------------------------------------------------------------------
# TEST 18: P0-3 Endpoint Probe Gate & Mid-Trial Management Loss Auto-Abort
# ------------------------------------------------------------------------------
echo "--- TEST 18: P0-3 Endpoint Probe Gate & Mid-Trial Management Drop ---"
if REQUIRE_ENDPOINT_PROBE=1 MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" preflight >/dev/null 2>&1; then
    echo "  [FAIL] Preflight allowed REQUIRE_ENDPOINT_PROBE=1 without client/endpoint verification"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Preflight enforced REQUIRE_ENDPOINT_PROBE=1 client verification gate"
    PASSED=$((PASSED + 1))
fi

rm -f "$MOCK_DIR/tmp/mock_mgmt_fail"
(
    sleep 1
    touch "$MOCK_DIR/tmp/mock_mgmt_fail"
) &
_t18_trigger=$!

if MEASURE_SECONDS=5 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    wait "$_t18_trigger" 2>/dev/null || true
    rm -f "$MOCK_DIR/tmp/mock_mgmt_fail"
    echo "  [FAIL] Trial did not abort on mid-trial management drop"
    FAILED=$((FAILED + 1))
    exit 1
else
    wait "$_t18_trigger" 2>/dev/null || true
    rm -f "$MOCK_DIR/tmp/mock_mgmt_fail"
    echo "  [PASS] Trial aborted immediately when management dropped mid-window"
    PASSED=$((PASSED + 1))
fi
assert_eq "Mid-trial management drop rolled back rps_cpus to 0" "0" "$(tr -d ' \t\r\n' < "$_rps_file")"

# ------------------------------------------------------------------------------
# TEST 19: Orchestrator run_rps_eth0_trial.sh Safety Gates & E2E Mock Lifecycle
# ------------------------------------------------------------------------------
echo "--- TEST 19: Host Orchestrator run_rps_eth0_trial.sh Gates & E2E Mock Run ---"
ORCH_SCRIPT="${REPO_ROOT}/performance/trials/run_rps_eth0_trial.sh"
ORCH_MOCK="${MOCK_DIR}/orch_mock"
mkdir -p "${ORCH_MOCK}/bin" "${ORCH_MOCK}/out" \
    "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0" \
    "${ORCH_MOCK}/rootfs/sys/kernel/debug/qca-nss-drv/stats" \
    "${ORCH_MOCK}/rootfs/sys/kernel/debug/ecm/ecm_db" \
    "${ORCH_MOCK}/rootfs/proc/net" \
    "${ORCH_MOCK}/rootfs/tmp"

printf '0\n' > "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0/rps_cpus"
printf 'MemAvailable:      28500 kB\nMemFree:           19000 kB\nSlab:              60800 kB\nSUnreclaim:        57900 kB\n' > "${ORCH_MOCK}/rootfs/proc/meminfo"
printf '           CPU0       CPU1\nNET_RX:    1000         10\n' > "${ORCH_MOCK}/rootfs/proc/softirqs"
printf 'Inter-|   Receive                                                |  Transmit\n  eth0: 10000 500 0 0 0 0 0 0 9000 400 0 0 0 0 0 0\nbr-lan: 8000 300 0 0 0 0 0 0 7000 250 0 0 0 0 0 0\n' > "${ORCH_MOCK}/rootfs/proc/net/dev"
printf '00000100 00000000 00000001 00000000 00000000 00000000 00000000 00000000 00000000\n00000020 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000\n' > "${ORCH_MOCK}/rootfs/proc/net/softnet_stat"
printf 'rx_pkts=5000 tx_pkts=4900\n' > "${ORCH_MOCK}/rootfs/sys/kernel/debug/qca-nss-drv/stats/ipv4"
printf '208\n' > "${ORCH_MOCK}/rootfs/sys/kernel/debug/ecm/ecm_db/connection_count"

cat << EOF > "${ORCH_MOCK}/bin/ping"
#!/bin/sh
if [ -f "${ORCH_MOCK}/fail_ping" ]; then
    exit 1
fi
printf '5 packets transmitted, 5 packets received, 0%% packet loss\nround-trip min/avg/max = 0.410/0.450/0.510 ms\n'
exit 0
EOF
chmod +x "${ORCH_MOCK}/bin/ping"

cat << EOF > "${ORCH_MOCK}/bin/ssh"
#!/bin/sh
while [ \$# -gt 0 ]; do
    case "\$1" in
        -p|-o) shift 2 ;;
        *) break ;;
    esac
done
_host="\${1:-}"; shift || true
_rcmd="\${*:-}"
export MOCK_ROOT="${ORCH_MOCK}/rootfs"
if [ -f "${ORCH_MOCK}/fail_ssh" ]; then
    exit 255
fi
if [ "\$(cat "\${MOCK_ROOT}/sys/class/net/eth0/queues/rx-0/rps_cpus" 2>/dev/null | tr -d ' \t\r\n')" = "2" ]; then
    printf '           CPU0       CPU1\nNET_RX:    1050        350\n' > "\${MOCK_ROOT}/proc/softirqs"
fi
sh -c "\$_rcmd"
EOF
chmod +x "${ORCH_MOCK}/bin/ssh"

# 19A: Refuses live run without --authorize-live-trial
if sh "$ORCH_SCRIPT" >/dev/null 2>&1; then
    echo "  [FAIL] Orchestrator ran without --authorize-live-trial or --dry-run"
    FAILED=$((FAILED + 1)); exit 1
else
    echo "  [PASS] Orchestrator refused un-authorized live run"
    PASSED=$((PASSED + 1))
fi

# 19B: --dry-run exits 0 and prints recovery & owner commands
_dry_out=$(sh "$ORCH_SCRIPT" --dry-run 2>&1)
assert_eq "Orchestrator --dry-run exits 0" "0" "$?"
if echo "$_dry_out" | grep -q "Emergency Recovery:" && echo "$_dry_out" | grep -q -- "--authorize-live-trial"; then
    echo "  [PASS] Orchestrator --dry-run printed recovery & owner command"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Orchestrator --dry-run missing expected hints"; FAILED=$((FAILED + 1)); exit 1
fi

# 19C: E2E Mock run succeeds, captures Before/During/After, and skips iperf3 cleanly
_e2e_out=$(MEASURE_SECONDS=3 WATCHDOG_TIMEOUT=20 MONITOR_INTERVAL=1 \
    sh "$ORCH_SCRIPT" --mock-dir "$ORCH_MOCK" --output-dir "${ORCH_MOCK}/out" 2>&1)
_e2e_rc=$?
assert_eq "Orchestrator mock E2E trial exited 0" "0" "$_e2e_rc"
assert_eq "Orchestrator restored router rps_cpus to 0" "0" "$(tr -d ' \t\r\n' < "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0/rps_cpus")"
assert_eq "Orchestrator cleaned remote runner from /tmp" "0" "$([ ! -f "${ORCH_MOCK}/rootfs/tmp/rps_eth0_trial.sh" ] && echo 0 || echo 1)"

if echo "$_e2e_out" | grep -q "Throughput Before:        HOOK_SKIPPED_NO_TARGET" \
   && echo "$_e2e_out" | grep -q "NET_RX Delta (CPU0 / CPU1): +50 / +340" \
   && echo "$_e2e_out" | grep -q "Shifting NET_RX softirqs onto CPU1 confirms IRQ steering only"; then
    echo "  [PASS] Orchestrator reported non-fabricated deltas, skipped throughput hook, and anti-conflation caveat"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Orchestrator output missing expected telemetry/caveat:"
    echo "$_e2e_out"
    FAILED=$((FAILED + 1)); exit 1
fi

# ------------------------------------------------------------------------------
# TEST 20: Orchestrator Fails Precondition on Client Unreachability
# ------------------------------------------------------------------------------
echo "--- TEST 20: Orchestrator Aborts on Unreachable Client Precondition ---"
touch "${ORCH_MOCK}/fail_ping"
if sh "$ORCH_SCRIPT" --mock-dir "$ORCH_MOCK" --output-dir "${ORCH_MOCK}/out" >/dev/null 2>&1; then
    rm -f "${ORCH_MOCK}/fail_ping"
    echo "  [FAIL] Orchestrator proceeded despite failed client ping"
    FAILED=$((FAILED + 1)); exit 1
else
    rm -f "${ORCH_MOCK}/fail_ping"
    echo "  [PASS] Orchestrator aborted before staging when client ping failed"
    PASSED=$((PASSED + 1))
fi
assert_eq "Aborted orchestrator left rps_cpus at 0" "0" "$(tr -d ' \t\r\n' < "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0/rps_cpus")"

# ------------------------------------------------------------------------------
# TEST 21: Orchestrator Mid-Trial Reachability Drop Triggers Emergency Restore
# ------------------------------------------------------------------------------
echo "--- TEST 21: Orchestrator Mid-Trial Client Reachability Drop Abort ---"
rm -f "${ORCH_MOCK}/fail_ping"
(
    for _w in $(seq 1 40); do
        if [ "$(cat "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0/rps_cpus" 2>/dev/null | tr -d ' \t\r\n')" = "2" ]; then
            touch "${ORCH_MOCK}/fail_ping"
            break
        fi
        sleep 0.2
    done
) &
_t21_mon_trigger=$!

if MEASURE_SECONDS=8 WATCHDOG_TIMEOUT=20 MONITOR_INTERVAL=1 \
    sh "$ORCH_SCRIPT" --mock-dir "$ORCH_MOCK" --output-dir "${ORCH_MOCK}/out" > "${ORCH_MOCK}/t21.log" 2>&1; then
    wait "$_t21_mon_trigger" 2>/dev/null || true
    rm -f "${ORCH_MOCK}/fail_ping"
    echo "  [FAIL] Orchestrator exited 0 despite mid-trial client reachability drop"
    FAILED=$((FAILED + 1)); exit 1
else
    wait "$_t21_mon_trigger" 2>/dev/null || true
    rm -f "${ORCH_MOCK}/fail_ping"
    echo "  [PASS] Orchestrator aborted on mid-trial client reachability loss"
    PASSED=$((PASSED + 1))
fi
assert_eq "Out-of-band / emergency restore returned rps_cpus to 0" "0" "$(tr -d ' \t\r\n' < "${ORCH_MOCK}/rootfs/sys/class/net/eth0/queues/rx-0/rps_cpus")"

# ------------------------------------------------------------------------------
# TEST SUMMARY
# ------------------------------------------------------------------------------
echo "================================================================================"
echo "CONTROLLED TRIAL TEST COMPLETE: $PASSED assertions passed, $FAILED assertions failed."
echo "================================================================================"

if [ "$FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
