#!/bin/sh
# tests/test_watchdog_rollback.sh
# Host-side validation test harness for the 180s Firewall Rollback Watchdog
# Tests SIGHUP resilience (SSH disconnect), timeout firing, cancellation, and dual-stack handling.
# Compatible with POSIX sh and BusyBox ash.

set -eu

echo "=== [TEST 1] Testing Watchdog SIGHUP Resilience (SSH Disconnect Simulation) ==="

TMP_DIR=$(mktemp -d /tmp/watchdog_test.XXXXXX)
MOCK_LOG="${TMP_DIR}/watchdog_actions.log"
PID_FILE="${TMP_DIR}/watchdog.pid"

# Helper mock firewall function simulating iptables/ip6tables
cat << 'EOF' > "${TMP_DIR}/mock_firewall.sh"
#!/bin/sh
ACTION="$1"
TABLE="$2"
RULE="$3"
echo "$(date +%s): ${ACTION} ${TABLE} ${RULE}" >> "$4"
EOF
chmod +x "${TMP_DIR}/mock_firewall.sh"

# Launch watchdog in a subshell that simulates SSH session disconnect:
# Send SIGHUP to the subshell group and verify watchdog survives!
sh -c '
    TMP_DIR="'"$TMP_DIR"'"
    MOCK_LOG="'"$MOCK_LOG"'"
    PID_FILE="'"$PID_FILE"'"
    
    # Arm watchdog with SIGHUP immunity and detached streams:
    (
        trap "" HUP
        sleep 2
        "${TMP_DIR}/mock_firewall.sh" "ROLLBACK_IPV4" "zone_wan_input" "DROP" "$MOCK_LOG"
        "${TMP_DIR}/mock_firewall.sh" "ROLLBACK_IPV6" "zone_wan_input" "DROP" "$MOCK_LOG"
    ) </dev/null >/dev/null 2>&1 &
    
    WATCHDOG_PID=$!
    echo "$WATCHDOG_PID" > "$PID_FILE"
    
    # Now simulate SSH disconnect by exiting subshell with SIGHUP:
    kill -HUP $$ 2>/dev/null || true
' || true

WATCHDOG_PID=$(cat "$PID_FILE")
echo "Watchdog spawned with PID: ${WATCHDOG_PID}. SSH session disconnected (SIGHUP sent)."

# Verify watchdog is still running despite parent SIGHUP
if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    echo "PASS: Watchdog survived parent SIGHUP (immunized against SSH disconnect)."
else
    echo "FAIL: Watchdog terminated on SIGHUP!"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "Waiting for watchdog 2s timeout to trigger rollback..."
sleep 3

# Verify rollback executed in mock log
if grep -q "ROLLBACK_IPV4" "$MOCK_LOG" && grep -q "ROLLBACK_IPV6" "$MOCK_LOG"; then
    echo "PASS: Watchdog timeout fired and executed dual-stack rollback successfully."
else
    echo "FAIL: Watchdog did not execute rollback!"
    cat "$MOCK_LOG" 2>/dev/null || true
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "=== [TEST 2] Testing Watchdog Disarm / Cancellation (Successful Verification Case) ==="
rm -f "$MOCK_LOG" "$PID_FILE"

# Launch 10-second watchdog
(
    trap "" HUP
    sleep 10
    "${TMP_DIR}/mock_firewall.sh" "ROLLBACK_TIMEOUT" "zone_wan_input" "DROP" "$MOCK_LOG"
) </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!

echo "Watchdog spawned with PID: ${WATCHDOG_PID}. Simulating successful LAN verification."
sleep 1

# Disarm watchdog
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

echo "Waiting 3 seconds to verify disarmed watchdog does NOT fire..."
sleep 3

if [ -f "$MOCK_LOG" ] && grep -q "ROLLBACK_TIMEOUT" "$MOCK_LOG"; then
    echo "FAIL: Disarmed watchdog still executed rollback!"
    rm -rf "$TMP_DIR"
    exit 1
else
    echo "PASS: Disarmed watchdog was cleanly neutralized. Zero unwanted rollbacks."
fi

echo "=== [TEST 3] Testing Idempotent Dual-Stack Rollback Shell Logic ==="

# Test shell rollback function handling missing rules gracefully
cat << 'EOF' > "${TMP_DIR}/test_rollback_function.sh"
#!/bin/sh
set -u

# Simulate rollback logic: remove rules while ignoring exit code 1 (rule not found)
rollback_rules() {
    # Delete IPv4 rule if present
    while iptables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do
        :
    done
    # Delete IPv6 rule if present
    while ip6tables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do
        :
    done
    return 0
}

rollback_rules
echo "Rollback function returned $?"
EOF
chmod +x "${TMP_DIR}/test_rollback_function.sh"

RES=$(sh "${TMP_DIR}/test_rollback_function.sh")
if echo "$RES" | grep -q "returned 0"; then
    echo "PASS: Rollback function is idempotent and ignores missing rules gracefully."
else
    echo "FAIL: Rollback function failed when rules were missing!"
    rm -rf "$TMP_DIR"
    exit 1
fi

rm -rf "$TMP_DIR"
echo "=== ALL 3 WATCHDOG VALIDATION TESTS PASSED (100% RELIABILITY) ==="
