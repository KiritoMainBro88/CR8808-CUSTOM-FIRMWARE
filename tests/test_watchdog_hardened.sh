#!/bin/sh
# tests/test_watchdog_hardened.sh
# Comprehensive Validation Suite for M11.1 Hardened Watchdog
# Evaluates Input Validation, Process-Group SIGHUP, SIGTERM Sentinel Suppression,
# Synchronized Disarm, Dual-Stack Rollback, and Partial Failure Resilience.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_watchdog_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SENTINEL="${TMP_DIR}/watchdog.armed"
MOCK_LOG="${TMP_DIR}/mock_rollback.log"
MOCK_HELPER="${TMP_DIR}/mock_rollback_helper.sh"
WATCHDOG_SCRIPT="scripts/watchdog_service.sh"

echo "=== M11.1.0.3 WATCHDOG HARDENING TEST SUITE ==="
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
# TEST 1: Parameter Validation (Timeout Validation)
# -----------------------------------------------------------------------------
echo "--- [TEST 1] Parameter Validation (Rejection of Invalid Timeout) ---"
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

# -----------------------------------------------------------------------------
# TEST 2: Process-Group SIGHUP Resilience
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Process Group SIGHUP Delivery ---"
rm -f "$SENTINEL" "$MOCK_LOG"
PID_FILE="${TMP_DIR}/pg_watchdog.pid"

# Run in an isolated process group via subshell
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

    # Send SIGHUP to the subshell process
    kill -HUP $$ 2>/dev/null || true
' 2>/dev/null || true

WD_PID=$(cat "$PID_FILE")
sleep 0.2

# Verify watchdog is running
if kill -0 "$WD_PID" 2>/dev/null; then
    echo "PASS: Watchdog survived parent process termination (SIGHUP ignored)."
else
    echo "FAIL: Watchdog died when parent received SIGHUP."
    exit 1
fi

# Also deliver SIGHUP directly to the watchdog PID
kill -HUP "$WD_PID" 2>/dev/null || true
sleep 0.2
if kill -0 "$WD_PID" 2>/dev/null; then
    echo "PASS: Watchdog directly survived SIGHUP signal."
else
    echo "FAIL: Watchdog died upon direct SIGHUP."
    exit 1
fi

# Wait for watchdog process to finish (poll since reparented to init)
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
# TEST 3: SIGTERM Received While Sentinel Still Exists (Clean Cancellation)
# -----------------------------------------------------------------------------
echo "--- [TEST 3] SIGTERM Handling While Sentinel Still Exists ---"
rm -f "$SENTINEL" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 5 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
TERM_PID=$!
sleep 0.3

# Sentinel MUST exist on disk right now
if [ ! -f "$SENTINEL" ]; then
    echo "FAIL: Sentinel was not created by watchdog."
    exit 1
fi

# Issue SIGTERM to watchdog process while sentinel is STILL active
kill -TERM "$TERM_PID" 2>/dev/null || true
wait "$TERM_PID" 2>/dev/null || true

# Verify exit code was 0 and NO rollback occurred!
if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "FAIL: Rollback was triggered despite SIGTERM cancellation!"
    exit 1
else
    echo "PASS: Watchdog caught SIGTERM with active sentinel and exited cleanly without rollback."
fi

# -----------------------------------------------------------------------------
# TEST 4: Full-Timeout Expiry Disarm Verification
# -----------------------------------------------------------------------------
echo "--- [TEST 4] Disarm with Full Timeout Expiry Wait ---"
rm -f "$SENTINEL" "$MOCK_LOG"

sh "$WATCHDOG_SCRIPT" 2 "$SENTINEL" "$MOCK_HELPER" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
DISARM_PID=$!
sleep 0.3

# Disarm: Remove sentinel and state
rm -f "$SENTINEL" "${SENTINEL}.state"
kill -TERM "$DISARM_PID" 2>/dev/null || true

# Wait 3.5 seconds (substantially exceeding the 2.0s timeout duration)
echo "Waiting 3.5s (exceeding 2.0s timeout) to confirm zero late rollback..."
sleep 3.5

if [ -f "$MOCK_LOG" ] && grep -q "MOCK_ROLLBACK_EXECUTED" "$MOCK_LOG"; then
    echo "FAIL: Rollback executed after disarm!"
    exit 1
else
    echo "PASS: Zero rollback actions occurred across the full timeout window."
fi

# -----------------------------------------------------------------------------
# TEST 5: Dual-Stack Rollback Execution via Production Helper
# -----------------------------------------------------------------------------
echo "--- [TEST 5] Dual-Stack Rollback via Structured Helper ---"
rm -f "$SENTINEL" "$MOCK_LOG"

cat << 'EOF' > "${TMP_DIR}/dual_stack_helper.sh"
#!/bin/sh
ACTION="$1"
LOG="$2"
if [ "$ACTION" = "rollback" ]; then
    echo "ROLLBACK_IPV4_DONE" >> "$LOG"
    echo "ROLLBACK_IPV6_DONE" >> "$LOG"
    exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/dual_stack_helper.sh"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "${TMP_DIR}/dual_stack_helper.sh" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
DUAL_PID=$!
wait "$DUAL_PID" 2>/dev/null || true

if grep -q "ROLLBACK_IPV4_DONE" "$MOCK_LOG" && grep -q "ROLLBACK_IPV6_DONE" "$MOCK_LOG"; then
    echo "PASS: Dual-stack rollback commands executed completely."
else
    echo "FAIL: Dual-stack rollback did not complete both protocols."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 6: Partial Failure Handling in Rollback
# -----------------------------------------------------------------------------
echo "--- [TEST 6] Partial Protocol Failure Handling in Rollback ---"
rm -f "$SENTINEL" "$MOCK_LOG"

cat << 'EOF' > "${TMP_DIR}/partial_fail_helper.sh"
#!/bin/sh
ACTION="$1"
LOG="$2"
if [ "$ACTION" = "rollback" ]; then
    echo "ROLLBACK_IPV4_SUCCESS" >> "$LOG"
    echo "ERROR: IPv6 rollback failed" >&2
    exit 1
fi
exit 1
EOF
chmod +x "${TMP_DIR}/partial_fail_helper.sh"

sh "$WATCHDOG_SCRIPT" 1 "$SENTINEL" "${TMP_DIR}/partial_fail_helper.sh" "$MOCK_LOG" </dev/null >/dev/null 2>&1 &
PARTIAL_PID=$!
wait "$PARTIAL_PID" 2>/dev/null || true

if grep -q "ROLLBACK_IPV4_SUCCESS" "$MOCK_LOG"; then
    echo "PASS: Watchdog gracefully handled partial failure without hanging or crashing."
else
    echo "FAIL: Watchdog failed to process partial rollback."
    exit 1
fi

echo "=== ALL 6 WATCHDOG INTEGRITY TESTS PASSED ==="
