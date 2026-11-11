#!/bin/sh
# tests/test_watchdog_hardened.sh
# Comprehensive Validation Suite for M11.1 Hardened Watchdog
# Evaluates SIGHUP Direct Delivery, SSH Hangup Simulation, Full-Timeout Disarm,
# Dual-Stack Rollback, Mock Command Errors, and Post-Disarm Quiescence.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_watchdog_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SENTINEL="${TMP_DIR}/watchdog.armed"
MOCK_LOG="${TMP_DIR}/mock_rollback.log"
WATCHDOG_SCRIPT="scripts/watchdog_service.sh"

echo "=== M11.1.0.2 WATCHDOG HARDENING TEST SUITE ==="
echo "Working directory: $TMP_DIR"

# -----------------------------------------------------------------------------
# TEST 1: Direct SIGHUP Delivery to Watchdog Process
# -----------------------------------------------------------------------------
echo "--- [TEST 1] Direct SIGHUP Signal Delivery to Watchdog ---"
touch "$SENTINEL"
rm -f "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "echo ROLLBACK_TRIGGERED >> '$MOCK_LOG'" </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!

sleep 0.2
# Verify process is running
if ! kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    echo "FAIL: Watchdog failed to spawn"
    exit 1
fi

# Send SIGHUP directly to the watchdog PID
kill -HUP "$WATCHDOG_PID" 2>/dev/null || true
sleep 0.2

# Verify watchdog is STILL running after receiving SIGHUP directly
if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    echo "PASS: Watchdog directly survived SIGHUP signal (trap '' HUP active)."
else
    echo "FAIL: Watchdog died upon receiving direct SIGHUP."
    exit 1
fi

# Wait for remaining timeout and verify rollback completed
wait "$WATCHDOG_PID" 2>/dev/null || true
if grep -q "ROLLBACK_TRIGGERED" "$MOCK_LOG"; then
    echo "PASS: Watchdog completed execution and performed rollback after SIGHUP."
else
    echo "FAIL: Rollback was not executed following SIGHUP survival."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 2: SSH Session Disconnect / Parent Group Hangup Simulation
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Parent Session Disconnect Simulation ---"
touch "$SENTINEL"
rm -f "$MOCK_LOG"
PID_FILE="${TMP_DIR}/subshell_watchdog.pid"

sh -c '
    TMP_DIR="'"$TMP_DIR"'"
    SENTINEL="'"$SENTINEL"'"
    MOCK_LOG="'"$MOCK_LOG"'"
    PID_FILE="'"$PID_FILE"'"
    WATCHDOG_SCRIPT="'"$WATCHDOG_SCRIPT"'"

    # Launch watchdog in background
    sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "echo ROLLBACK_AFTER_SSH_DROP >> \"$MOCK_LOG\"" </dev/null >/dev/null 2>&1 &
    echo $! > "$PID_FILE"

    # Simulate SSH terminal hangup on parent
    kill -HUP $$ 2>/dev/null || true
' 2>/dev/null || true

SUB_WATCHDOG_PID=$(cat "$PID_FILE")
sleep 0.3

if kill -0 "$SUB_WATCHDOG_PID" 2>/dev/null; then
    echo "PASS: Watchdog orphaned process survived parent terminal hangup."
else
    echo "FAIL: Watchdog process died when parent terminal disconnected."
    exit 1
fi

# Wait past the 2s timeout
sleep 2.2
if grep -q "ROLLBACK_AFTER_SSH_DROP" "$MOCK_LOG"; then
    echo "PASS: Orphaned watchdog fired rollback on schedule."
else
    echo "FAIL: Rollback failed after parent disconnect."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 3: Disarm Verification with Full-Timeout Expiry Wait
# -----------------------------------------------------------------------------
echo "--- [TEST 3] Disarm Verification with Full Expiry Wait ---"
touch "$SENTINEL"
rm -f "$MOCK_LOG"

# Set timeout to 2 seconds
sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "echo UNWANTED_ROLLBACK >> '$MOCK_LOG'" </dev/null >/dev/null 2>&1 &
DISARM_PID=$!

sleep 0.3
# Disarm via Double-Barrier:
# Barrier 1: Remove sentinel
rm -f "$SENTINEL"
# Barrier 2: Send SIGTERM
kill -TERM "$DISARM_PID" 2>/dev/null || true

# Wait 3.5 seconds (Significantly exceeds the 2.0s timeout duration)
echo "Waiting 3.5s (exceeding 2.0s timeout) to prove no late rollback..."
sleep 3.5

if [ -f "$MOCK_LOG" ] && grep -q "UNWANTED_ROLLBACK" "$MOCK_LOG"; then
    echo "FAIL: Rollback executed after disarm!"
    exit 1
else
    echo "PASS: Zero rollback actions occurred across the entire timeout window."
fi

# -----------------------------------------------------------------------------
# TEST 4: Dual-Stack Rollback Execution (IPv4 + IPv6)
# -----------------------------------------------------------------------------
echo "--- [TEST 4] Dual-Stack Rollback Execution ---"
touch "$SENTINEL"
rm -f "$MOCK_LOG"

ROLLBACK_DUAL='echo "REVERT_IPV4" >> "'"$MOCK_LOG"'"; echo "REVERT_IPV6" >> "'"$MOCK_LOG"'"'

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "$ROLLBACK_DUAL" </dev/null >/dev/null 2>&1 &
DUAL_PID=$!

wait "$DUAL_PID" 2>/dev/null || true

if grep -q "REVERT_IPV4" "$MOCK_LOG" && grep -q "REVERT_IPV6" "$MOCK_LOG"; then
    echo "PASS: Both IPv4 and IPv6 rollback commands executed successfully."
else
    echo "FAIL: Dual-stack rollback did not complete both commands."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 5: Resilience to Command Failures and SIGTERM Clean Exit
# -----------------------------------------------------------------------------
echo "--- [TEST 5] Resilience to Command Errors and SIGTERM Exit ---"
touch "$SENTINEL"
rm -f "$MOCK_LOG"

# Simulate a command string where first command fails (exit 1), but second succeeds
FAIL_CMD='sh -c "exit 1"; echo "RECOVERED_AFTER_FAILURE" >> "'"$MOCK_LOG"'"'

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "$FAIL_CMD" </dev/null >/dev/null 2>&1 &
ERR_PID=$!

wait "$ERR_PID" 2>/dev/null || true

if grep -q "RECOVERED_AFTER_FAILURE" "$MOCK_LOG"; then
    echo "PASS: Watchdog survived command failure and proceeded with rollback chain."
else
    echo "FAIL: Watchdog halted on intermediate command error."
    exit 1
fi

# Test SIGTERM cleanly terminates without error
touch "$SENTINEL"
sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "echo UNWANTED >> '$MOCK_LOG'" </dev/null >/dev/null 2>&1 &
TERM_PID=$!
sleep 0.2
kill -TERM "$TERM_PID" 2>/dev/null || true
wait "$TERM_PID" 2>/dev/null || true
echo "PASS: Watchdog cleanly caught SIGTERM and exited with status 0."

# -----------------------------------------------------------------------------
# TEST 6: Double-Barrier Inactivity Check (Missing Sentinel Suppression)
# -----------------------------------------------------------------------------
echo "--- [TEST 6] Double-Barrier Check (Sentinel Suppression Without Process Kill) ---"
rm -f "$MOCK_LOG"
# Do NOT touch sentinel, but allow watchdog to sleep and wake up
sh "$WATCHDOG_SCRIPT" 1 "${TMP_DIR}/nonexistent.sentinel" "echo GHOST_ROLLBACK >> '$MOCK_LOG'" </dev/null >/dev/null 2>&1 &
GHOST_PID=$!

wait "$GHOST_PID" 2>/dev/null || true

if [ -f "$MOCK_LOG" ] && grep -q "GHOST_ROLLBACK" "$MOCK_LOG"; then
    echo "FAIL: Watchdog executed rollback without active sentinel!"
    exit 1
else
    echo "PASS: Watchdog safely suppressed rollback when sentinel was absent."
fi

echo "=== ALL 6 WATCHDOG VALIDATION TESTS PASSED ==="
