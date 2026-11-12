#!/bin/sh
# tests/test_watchdog_hardened.sh
# Comprehensive Validation Suite for M11.1 Hardened Watchdog
# Evaluates Input Verification ($# < 3), Timeout Validation (1..86400),
# Mutual Exclusion Lock, Blocking Restart on Unhandled Failures (SLEEP/ROLLBACK_FAILED),
# Race Condition Prevention (Disarm vs ROLLING_BACK), Atomic Disarm,
# Process-Group SIGHUP Immunity, SIGTERM Cancellation, Positional Argument Preservation,
# Sleep Failure Abort, and 3-Attempt Rollback Retry with Forensic State Preservation.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_watchdog_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SENTINEL="${TMP_DIR}/watchdog.armed"
MOCK_LOG="${TMP_DIR}/mock_rollback.log"
MOCK_HELPER="${TMP_DIR}/mock_rollback_helper.sh"
WATCHDOG_SCRIPT="scripts/watchdog_service.sh"

echo "=== M11.1.0.5 WATCHDOG HARDENING TEST SUITE ==="
echo "Working directory: $TMP_DIR"

# Create a baseline mock rollback helper
cat << 'EOF' > "$MOCK_HELPER"
#!/bin/sh
ACTION="$1"
LOG="$2"
if [ "$ACTION" = "rollback" ]; then
    echo "MOCK_ROLLBACK_EXECUTED" >> "$LOG"
    exit 0
else
    echo "UNKNOWN_ACTION" >> "$LOG"
    exit 1
fi
EOF
chmod +x "$MOCK_HELPER"

# -----------------------------------------------------------------------------
# TEST 1: Missing Argument Count Validation ($# < 3)
# -----------------------------------------------------------------------------
echo "--- [TEST 1] Missing Argument Count Validation ($# < 3) ---"
if sh "$WATCHDOG_SCRIPT" 2>/dev/null; then
    echo "FAIL: Watchdog accepted 0 arguments!"
    exit 1
else
    echo "PASS: 0 arguments correctly rejected."
fi

if sh "$WATCHDOG_SCRIPT" 10 2>/dev/null; then
    echo "FAIL: Watchdog accepted 1 argument!"
    exit 1
else
    echo "PASS: 1 argument correctly rejected."
fi

if sh "$WATCHDOG_SCRIPT" 10 "$SENTINEL" 2>/dev/null; then
    echo "FAIL: Watchdog accepted 2 arguments!"
    exit 1
else
    echo "PASS: 2 arguments correctly rejected."
fi

# -----------------------------------------------------------------------------
# TEST 2: Parameter Validation (Timeout Bounds 1..86400)
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Parameter Validation (Timeout Bounds 1..86400) ---"
if sh "$WATCHDOG_SCRIPT" "invalid_timeout" "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog accepted non-numeric timeout!"
    exit 1
else
    echo "PASS: Non-numeric timeout correctly rejected."
fi

if sh "$WATCHDOG_SCRIPT" "-10" "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog accepted negative timeout!"
    exit 1
else
    echo "PASS: Negative timeout correctly rejected."
fi

if sh "$WATCHDOG_SCRIPT" "0" "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog accepted zero timeout!"
    exit 1
else
    echo "PASS: Zero timeout correctly rejected."
fi

if sh "$WATCHDOG_SCRIPT" "99999" "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog accepted timeout > 86400!"
    exit 1
else
    echo "PASS: Timeout > 86400 correctly rejected."
fi

# -----------------------------------------------------------------------------
# TEST 3: Mutual Exclusion Collision Detection
# -----------------------------------------------------------------------------
echo "--- [TEST 3] Mutual Exclusion Collision Detection ---"
rm -f "$SENTINEL" "$MOCK_LOG" "${SENTINEL}.lock"
sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
WD1_PID=$!
sleep 0.3

# Attempt to start a second watchdog with the identical sentinel file
if sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Second concurrent watchdog was not rejected!"
    kill -TERM "$WD1_PID" 2>/dev/null || true
    exit 1
else
    echo "PASS: Second concurrent watchdog rejected due to active lock."
fi
kill -TERM "$WD1_PID" 2>/dev/null || true
wait "$WD1_PID" 2>/dev/null || true
rm -rf "${SENTINEL}.lock" "$SENTINEL" "${SENTINEL}.state"

# -----------------------------------------------------------------------------
# TEST 4: Block Restart on Unhandled ROLLBACK_FAILED or SLEEP_FAILED
# -----------------------------------------------------------------------------
echo "--- [TEST 4] Block Restart on Unhandled Failure States ---"
# Test 4A: Block on ROLLBACK_FAILED
echo "ROLLBACK_FAILED" > "${SENTINEL}.state"
if sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog started despite existing ROLLBACK_FAILED state!"
    exit 1
else
    echo "PASS: Watchdog correctly refused to overwrite unhandled ROLLBACK_FAILED state."
fi

# Test 4B: Block on SLEEP_FAILED
echo "SLEEP_FAILED" > "${SENTINEL}.state"
if sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" 2>/dev/null; then
    echo "FAIL: Watchdog started despite existing SLEEP_FAILED state!"
    exit 1
else
    echo "PASS: Watchdog correctly refused to overwrite unhandled SLEEP_FAILED state."
fi
rm -f "${SENTINEL}.state"

# -----------------------------------------------------------------------------
# TEST 5: Race Condition Prevention – Disarm Rejected when ROLLING_BACK
# -----------------------------------------------------------------------------
echo "--- [TEST 5] Race Condition Prevention (Disarm vs ROLLING_BACK) ---"
touch "$SENTINEL"
echo "ROLLING_BACK" > "${SENTINEL}.state"

if sh "$WATCHDOG_SCRIPT" disarm "$SENTINEL" 2>/dev/null; then
    echo "FAIL: Disarm succeeded when state was already ROLLING_BACK!"
    exit 1
else
    echo "PASS: Disarm correctly rejected when state was already ROLLING_BACK."
fi

# Verify sentinel was NOT deleted
if [ -f "$SENTINEL" ]; then
    echo "PASS: Sentinel file was preserved when disarm was rejected."
else
    echo "FAIL: Sentinel was deleted despite disarm rejection!"
    exit 1
fi
rm -f "$SENTINEL" "${SENTINEL}.state"

# -----------------------------------------------------------------------------
# TEST 6: Atomic Disarm Operation (Before Expiry)
# -----------------------------------------------------------------------------
echo "--- [TEST 6] Atomic Disarm Operation ---"
rm -f "$SENTINEL" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
DISARM_WD_PID=$!
sleep 0.3

# Sentinel MUST exist
if [ ! -f "$SENTINEL" ]; then
    echo "FAIL: Sentinel was not created by watchdog."
    exit 1
fi

# Execute atomic disarm
if sh "$WATCHDOG_SCRIPT" disarm "$SENTINEL"; then
    echo "PASS: Disarm command returned success."
else
    echo "FAIL: Disarm command failed!"
    exit 1
fi

# Verify state is DISARMED and sentinel is deleted
if [ ! -f "$SENTINEL" ]; then
    echo "PASS: Sentinel was deleted by disarm command."
else
    echo "FAIL: Sentinel still exists after disarm!"
    exit 1
fi

wait "$DISARM_WD_PID" 2>/dev/null || true

# Verify zero rollback executed
if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "FAIL: Rollback was executed despite disarm!"
    exit 1
else
    echo "PASS: Zero rollback actions occurred after disarm."
fi

# -----------------------------------------------------------------------------
# TEST 7: Process-Group SIGHUP Resilience
# -----------------------------------------------------------------------------
echo "--- [TEST 7] Process Group SIGHUP Delivery ---"
rm -f "$SENTINEL" "$MOCK_LOG"
PID_FILE="${TMP_DIR}/pg_watchdog.pid"

sh -c '
    TMP_DIR="'"$TMP_DIR"'"
    SENTINEL="'"$SENTINEL"'"
    MOCK_LOG="'"$MOCK_LOG"'"
    MOCK_HELPER="'"$MOCK_HELPER"'"
    PID_FILE="'"$PID_FILE"'"
    WATCHDOG_SCRIPT="'"$WATCHDOG_SCRIPT"'"

    sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
    WD_PID=$!
    echo "$WD_PID" > "$PID_FILE"

    kill -HUP $$ 2>/dev/null || true
' 2>/dev/null || true

WD_PID=$(cat "$PID_FILE")
sleep 0.2

if kill -0 "$WD_PID" 2>/dev/null; then
    echo "PASS: Watchdog survived parent process termination (SIGHUP ignored)."
else
    echo "FAIL: Watchdog died when parent received SIGHUP."
    exit 1
fi

kill -HUP "$WD_PID" 2>/dev/null || true
sleep 0.2
if kill -0 "$WD_PID" 2>/dev/null; then
    echo "PASS: Watchdog directly survived SIGHUP signal."
else
    echo "FAIL: Watchdog died upon direct SIGHUP."
    exit 1
fi

while kill -0 "$WD_PID" 2>/dev/null; do
    sleep 0.2
done

if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "PASS: Scheduled rollback executed successfully after SIGHUP."
else
    echo "FAIL: Rollback did not execute after SIGHUP."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 8: SIGTERM Received While Sentinel Exists (Triggers Emergency Rollback)
# -----------------------------------------------------------------------------
echo "--- [TEST 8] Unexpected SIGTERM Handling (Emergency Rollback Trigger) ---"
rm -f "$SENTINEL" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 10 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
TERM_PID=$!
sleep 0.3

if [ ! -f "$SENTINEL" ]; then
    echo "FAIL: Sentinel was not created by watchdog."
    exit 1
fi

# Send SIGTERM to watchdog while ARMED (without disarm)
kill -TERM "$TERM_PID" 2>/dev/null || true
wait "$TERM_PID" 2>/dev/null || true

# Assert emergency rollback was EXECUTED
if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "PASS: Watchdog caught unexpected SIGTERM while ARMED and executed emergency rollback."
else
    echo "FAIL: Watchdog died upon SIGTERM without executing emergency rollback!"
    exit 1
fi

if [ -f "${SENTINEL}.state" ] && grep -q "SIGNAL_ROLLBACK_COMPLETED" "${SENTINEL}.state"; then
    echo "PASS: State recorded SIGNAL_ROLLBACK_COMPLETED."
else
    echo "FAIL: State file did not record SIGNAL_ROLLBACK_COMPLETED!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 9: Zero-Eval Positional Parameter Preservation (Spaces in Arguments)
# -----------------------------------------------------------------------------
echo "--- [TEST 9] Zero-Eval Positional Parameter Preservation (\"$@\") ---"
rm -f "$SENTINEL" "$MOCK_LOG"

cat << 'EOF' > "${TMP_DIR}/spaces_helper.sh"
#!/bin/sh
ACTION="$1"
LOG="$2"
ARG1="$3"
ARG2="$4"
if [ "$ACTION" = "rollback" ]; then
    echo "PARAM1:[$ARG1]" >> "$LOG"
    echo "PARAM2:[$ARG2]" >> "$LOG"
    exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/spaces_helper.sh"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "${TMP_DIR}/spaces_helper.sh" "$MOCK_LOG" "arg with multiple spaces" "second arg with spaces" </dev/null >/dev/null 2>&1 &
SPACES_PID=$!
wait "$SPACES_PID" 2>/dev/null || true

if grep -q "PARAM1:\[arg with multiple spaces\]" "$MOCK_LOG" && grep -q "PARAM2:\[second arg with spaces\]" "$MOCK_LOG"; then
    echo "PASS: Positional arguments with spaces preserved perfectly via \"$@\"."
else
    echo "FAIL: Positional arguments with spaces were corrupted!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 10: Sleep Failure while ARMED triggers Emergency Rollback (SLEEP_FAILED_ROLLED_BACK)
# -----------------------------------------------------------------------------
echo "--- [TEST 10] Sleep Failure Abort Handling with Emergency Rollback ---"
rm -f "$SENTINEL" "$MOCK_LOG" "${SENTINEL}.state"

sh "$WATCHDOG_SCRIPT" 10 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
SLEEP_WD_PID=$!
sleep 0.3

SLEEP_CHILD_PID=$(pgrep -P "$SLEEP_WD_PID" sleep 2>/dev/null || true)
if [ -n "$SLEEP_CHILD_PID" ]; then
    kill -KILL "$SLEEP_CHILD_PID" 2>/dev/null || true
fi
wait "$SLEEP_WD_PID" 2>/dev/null || true

if [ -f "${SENTINEL}.state" ] && grep -q "SLEEP_FAILED_ROLLED_BACK" "${SENTINEL}.state"; then
    echo "PASS: Watchdog correctly executed emergency rollback and recorded SLEEP_FAILED_ROLLED_BACK."
else
    echo "FAIL: Expected SLEEP_FAILED_ROLLED_BACK state missing."
    exit 1
fi

if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "PASS: Emergency rollback helper was invoked after sleep failure."
else
    echo "FAIL: Emergency rollback was NOT triggered when sleep failed!"
    exit 1
fi
rm -f "${SENTINEL}.state" "$MOCK_LOG"

# -----------------------------------------------------------------------------
# TEST 11: Rollback Helper Failure with 3 Retries and State Preservation
# -----------------------------------------------------------------------------
echo "--- [TEST 11] Rollback Helper Failure with 3 Retries & State Preservation ---"
rm -f "$SENTINEL" "$MOCK_LOG" "${SENTINEL}.state" "${SENTINEL}.error.log"

cat << 'EOF' > "${TMP_DIR}/failing_helper.sh"
#!/bin/sh
ACTION="$1"
LOG="$2"
echo "FAILING_HELPER_INVOKED" >> "$LOG"
exit 1
EOF
chmod +x "${TMP_DIR}/failing_helper.sh"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "${TMP_DIR}/failing_helper.sh" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
FAIL_WD_PID=$!
wait "$FAIL_WD_PID" 2>/dev/null || true

ATTEMPTS=$(grep -c "FAILING_HELPER_INVOKED" "$MOCK_LOG" || echo 0)
if [ "$ATTEMPTS" -eq 3 ]; then
    echo "PASS: Rollback helper was retried exactly 3 times."
else
    echo "FAIL: Expected 3 attempts, got $ATTEMPTS."
    exit 1
fi

if [ -f "${SENTINEL}.state" ] && grep -q "ROLLBACK_FAILED" "${SENTINEL}.state"; then
    echo "PASS: Watchdog recorded ROLLBACK_FAILED in state file."
else
    echo "FAIL: Expected ROLLBACK_FAILED in state file."
    exit 1
fi

if [ -f "$SENTINEL" ] && [ -f "${SENTINEL}.error.log" ]; then
    echo "PASS: Sentinel file and error log were preserved for forensics."
else
    echo "FAIL: Sentinel or error log deleted after rollback failure!"
    exit 1
fi

if grep -q "ROLLBACK_COMPLETED" "${SENTINEL}.state"; then
    echo "FAIL: ROLLBACK_COMPLETED was recorded on failure!"
    exit 1
else
    echo "PASS: ROLLBACK_COMPLETED was NOT recorded."
fi

# -----------------------------------------------------------------------------
# TEST 12: Strict Lock Ownership (Zero Deletion of Foreign TRANS_LOCK)
# -----------------------------------------------------------------------------
echo "--- [TEST 12] Strict Lock Ownership Enforcement (ACQ=1 Requirement) ---"
rm -rf "$SENTINEL" "${SENTINEL}.lock" "${SENTINEL}.trans.lock" "${SENTINEL}.state" "${SENTINEL}.error.log" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
CONTENTION_PID=$!
sleep 0.2

# Foreign process creates and holds the transition lock
mkdir "${SENTINEL}.trans.lock" 2>/dev/null || true
echo "FOREIGN_OWNER" > "${SENTINEL}.trans.lock/owner"

# Wait for watchdog to time out and attempt lock acquisition
wait "$CONTENTION_PID" 2>/dev/null || true

# Assert foreign lock was NEVER deleted by the watchdog
if [ -d "${SENTINEL}.trans.lock" ] && [ -f "${SENTINEL}.trans.lock/owner" ]; then
    echo "PASS: Foreign transition lock was PRESERVED (no unauthorized deletion when ACQ=0)."
else
    echo "FAIL: Foreign transition lock was deleted by un-authenticated process!"
    exit 1
fi
rm -rf "$SENTINEL" "${SENTINEL}.lock" "${SENTINEL}.trans.lock" "${SENTINEL}.state" "${SENTINEL}.error.log"

# -----------------------------------------------------------------------------
# TEST 13: Disarm Race Resolution via Transition Lock
# -----------------------------------------------------------------------------
echo "--- [TEST 13] Disarm Race Resolution via Transition Lock ---"
rm -rf "$SENTINEL" "${SENTINEL}.lock" "${SENTINEL}.trans.lock" "${SENTINEL}.state" "${SENTINEL}.error.log" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
RACE_WD_PID=$!
sleep 0.3

# Invoke authorized disarm
sh "$WATCHDOG_SCRIPT" disarm "$SENTINEL"
DISARM_RET=$?
wait "$RACE_WD_PID" 2>/dev/null || true

if [ "$DISARM_RET" -eq 0 ]; then
    echo "PASS: Authorized disarm completed successfully."
else
    echo "FAIL: Authorized disarm returned non-zero code $DISARM_RET."
    exit 1
fi

if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "FAIL: Rollback executed despite authorized disarm!"
    exit 1
else
    echo "PASS: Zero rollback executed following authorized disarm."
fi
rm -rf "$SENTINEL" "${SENTINEL}.lock" "${SENTINEL}.trans.lock" "${SENTINEL}.state" "${SENTINEL}.error.log"

# -----------------------------------------------------------------------------
# TEST 14: Independent Rule Verification via Helper verify_clean
# -----------------------------------------------------------------------------
echo "--- [TEST 14] Independent Rule Verification Post-Rollback ---"
rm -rf "$SENTINEL" "${SENTINEL}.lock" "${SENTINEL}.trans.lock" "${SENTINEL}.state" "${SENTINEL}.error.log" "$MOCK_LOG"

cat << 'EOF' > "${TMP_DIR}/verifying_helper.sh"
#!/bin/sh
ACTION="$1"
LOG="$2"
if [ "$ACTION" = "rollback" ]; then
    echo "ROLLBACK_CALLED" >> "$LOG"
    exit 0
elif [ "$ACTION" = "verify_clean" ]; then
    echo "VERIFY_CLEAN_CALLED" >> "$LOG"
    exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/verifying_helper.sh"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "${TMP_DIR}/verifying_helper.sh" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
VERIFY_WD_PID=$!
wait "$VERIFY_WD_PID" 2>/dev/null || true

if grep -q "ROLLBACK_CALLED" "$MOCK_LOG" && grep -q "VERIFY_CLEAN_CALLED" "$MOCK_LOG"; then
    echo "PASS: Watchdog invoked rollback and independently verified clean state via helper."
else
    echo "FAIL: Watchdog failed to invoke verify_clean on helper!"
    exit 1
fi

echo "=== ALL 14 WATCHDOG HARDENING TESTS PASSED ==="
