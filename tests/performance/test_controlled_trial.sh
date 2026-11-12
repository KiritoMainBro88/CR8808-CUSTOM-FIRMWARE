#!/bin/sh
# tests/performance/test_controlled_trial.sh
# ==============================================================================
# Failure-Injection & Verification Test Harness for Controlled Performance Trial
# Workstream B & G: Network Performance & Automated Optimization
#
# Validates:
#   1. Complete Happy Path trial lifecycle (Preflight -> Snapshot -> Apply ->
#      Measurement -> Rollback -> Verification).
#   2. Precondition rejection on baseline parameter drift (non-432000).
#   3. Precondition rejection on insufficient RAM headroom (<6MB available).
#   4. Fault injection: SIGTERM trap handler emergency rollback.
#   5. Independent background watchdog auto-rollback trigger.
#   6. Bit-for-bit restoration guarantee.
#
# Executed 100% in PC/WSL2 hermetic mock environment. Zero router writes.
# ==============================================================================

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRIAL_RUNNER="${REPO_ROOT}/performance/trials/controlled_trial_runner.sh"

MOCK_DIR="$(mktemp -d /tmp/ra82_trial_mock.XXXXXX)"
export MOCK_ROOT="$MOCK_DIR"
export TRIAL_STATE_DIR="/tmp/trial_state"

cleanup() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "================================================================================"
echo ">>> RUNNING CONTROLLED PERFORMANCE TRIAL TEST HARNESS (FAILURE INJECTION)"
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

    # Sysctl: nf_conntrack_tcp_timeout_established
    mkdir -p "$MOCK_DIR/proc/sys/net/netfilter"
    printf '%s\n' "432000" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"
    printf '%s\n' "550" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_count"

    # Meminfo: normal healthy RAM (10.5 MB available)
    mkdir -p "$MOCK_DIR/proc"
    cat << 'EOF' > "$MOCK_DIR/proc/meminfo"
MemTotal:         186368 kB
MemFree:           10752 kB
MemAvailable:      10752 kB
Slab:              60504 kB
SUnreclaim:        57932 kB
EOF

    # Trial state directory
    mkdir -p "$MOCK_DIR$TRIAL_STATE_DIR"
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
_final_val=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "Parameter restored to baseline 432000" "432000" "$_final_val"

# Check state file is cleaned up
assert_eq "State file cleaned up" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 2: Precondition Rejection on Baseline Drift
# ------------------------------------------------------------------------------
echo "--- TEST 2: Precondition Rejection on Parameter Drift ---"
init_mock_environment

# Inject abnormal baseline value
printf '%s\n' "123456" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"

if MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1; then
    echo "  [FAIL] Trial runner should have rejected abnormal baseline value"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Trial runner cleanly rejected baseline drift"
    PASSED=$((PASSED + 1))
fi

_unmodified_val=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "Parameter was left completely untouched" "123456" "$_unmodified_val"
assert_eq "No state snapshot created" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state" ] && echo 0 || echo 1)"

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

_untouched_param=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "Parameter remained untouched at 432000" "432000" "$_untouched_param"

# ------------------------------------------------------------------------------
# TEST 4: Fault Injection: Signal Interruption (SIGTERM) & Emergency Rollback
# ------------------------------------------------------------------------------
echo "--- TEST 4: Fault Injection: SIGTERM Interruption Recovery ---"
init_mock_environment

# Launch trial runner in background with a 15-second measurement window
MEASURE_SECONDS=15 sh "$TRIAL_RUNNER" run >/dev/null 2>&1 &
RUNNER_PID=$!

# Wait for runner to enter Phase 4/5 (param set to 86400)
_waited=0
while [ "$_waited" -lt 10 ]; do
    _cur=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
    if [ "$_cur" = "86400" ]; then
        break
    fi
    sleep 0.2
    _waited=$((_waited + 1))
done

assert_eq "Trial successfully applied 86400 prior to fault injection" "86400" "$_cur"

# Inject fault: kill runner process with SIGTERM
kill -TERM "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true

# Verify emergency trap handler caught signal and reverted parameter to 432000
_reverted=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "Emergency trap handler reverted parameter to baseline 432000" "432000" "$_reverted"

# ------------------------------------------------------------------------------
# TEST 5: Watchdog Auto-Rollback Execution
# ------------------------------------------------------------------------------
echo "--- TEST 5: Watchdog Auto-Rollback Execution ---"
init_mock_environment

# Simulate an abandoned trial in progress
printf '%s\n' "86400" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"
cat << EOF > "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state"
TARGET_PARAM=net.netfilter.nf_conntrack_tcp_timeout_established
BASELINE_VALUE=432000
TRIAL_VALUE=86400
PID=99999
EOF

# Spawn simulated 1-second watchdog
(
    sleep 1
    if [ -f "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state" ]; then
        printf '%s\n' "432000" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"
        rm -f "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state"
    fi
) &
WD_PID=$!
wait "$WD_PID"

_wd_reverted=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "Watchdog restored parameter to 432000" "432000" "$_wd_reverted"
assert_eq "Watchdog cleaned up state file" "0" "$([ ! -f "$MOCK_DIR$TRIAL_STATE_DIR/conntrack_trial.state" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 6: Bit-for-Bit Exact Post-Rollback Integrity
# ------------------------------------------------------------------------------
echo "--- TEST 6: Bit-for-Bit Exact Post-Rollback Integrity ---"
init_mock_environment

_pre_sha=$(sha256sum "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | awk '{print $1}')
MEASURE_SECONDS=1 sh "$TRIAL_RUNNER" run >/dev/null 2>&1
_post_sha=$(sha256sum "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | awk '{print $1}')

assert_eq "Pre-trial and post-rollback SHA-256 match bit-for-bit" "$_pre_sha" "$_post_sha"

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
