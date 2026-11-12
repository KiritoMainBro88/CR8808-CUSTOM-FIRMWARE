#!/bin/sh
# tests/test_firewall_ownership.sh
# Empirical Test Harness for Firewall Rule Ownership, Position 1 Verification,
# Production Helper Integration, Dynamic Chain Isolation, and Failure Injection.
# Executed via real Linux netfilter in WSL2.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_fw_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Generate unique, non-colliding dynamic chain names using PID and timestamp (max 28 chars for iptables)
UNIQUE_SUFFIX="$$-$(date +%s)"
CHAIN_V4="M11_V4_${UNIQUE_SUFFIX}"
CHAIN_V6="M11_V6_${UNIQUE_SUFFIX}"
TAG="M11_1_TRIAL_SSH_BLOCK"
PORT="56789"
HELPER="scripts/firewall_manager.sh"

echo "=== M11.1.0.5 FIREWALL OWNERSHIP & TRANSACTIONAL SAFETY TEST ==="
echo "Dynamic Test Chains: $CHAIN_V4 (IPv4), $CHAIN_V6 (IPv6)"

# Selective cleanup function: ONLY removes chains verified to be created by this run
CREATED_V4=""
CREATED_V6=""

cleanup() {
    echo "Cleaning up dynamic test chains..."
    if [ -n "$CREATED_V4" ]; then
        if sudo iptables -L "$CREATED_V4" -n >/dev/null 2>&1; then
            sudo iptables -F "$CREATED_V4" 2>/dev/null || true
            sudo iptables -X "$CREATED_V4" 2>/dev/null || true
        fi
    fi
    if [ -n "$CREATED_V6" ]; then
        if sudo ip6tables -L "$CREATED_V6" -n >/dev/null 2>&1; then
            sudo ip6tables -F "$CREATED_V6" 2>/dev/null || true
            sudo ip6tables -X "$CREATED_V6" 2>/dev/null || true
        fi
    fi
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# SETUP: Create isolated dynamic test chains representing zone_wan_input
# -----------------------------------------------------------------------------
sudo iptables -N "$CHAIN_V4"
CREATED_V4="$CHAIN_V4"
sudo ip6tables -N "$CHAIN_V6"
CREATED_V6="$CHAIN_V6"

# Inject pre-existing baseline rules into IPv4:
# Rule A: HTTP accept rule
sudo iptables -A "$CHAIN_V4" -p tcp --dport 80 -j ACCEPT
# Rule B: Pre-existing DROP on port 56789 WITHOUT comment (historical rule)
sudo iptables -A "$CHAIN_V4" -p tcp --dport "$PORT" -j DROP
# Rule C: DNS accept rule
sudo iptables -A "$CHAIN_V4" -p udp --dport 53 -j ACCEPT

# Inject pre-existing baseline rule into IPv6:
sudo ip6tables -A "$CHAIN_V6" -p tcp --dport "$PORT" -j DROP

INITIAL_COUNT_V4=$(sudo iptables -S "$CHAIN_V4" | grep -c '^-A')
INITIAL_COUNT_V6=$(sudo ip6tables -S "$CHAIN_V6" | grep -c '^-A')

echo "Pre-existing baseline rules: IPv4 = $INITIAL_COUNT_V4 rules, IPv6 = $INITIAL_COUNT_V6 rules."

# -----------------------------------------------------------------------------
# TEST 1: Production Helper Apply with Position 1 Verification
# -----------------------------------------------------------------------------
echo "--- [TEST 1] Applying Trial Rules via Production Helper ---"
IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
  sh "$HELPER" apply "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG"

# Verify exact Rule Position 1 using iptables -S <chain> 1
FIRST_RULE_V4=$(sudo iptables -S "$CHAIN_V4" 1)
FIRST_RULE_V6=$(sudo ip6tables -S "$CHAIN_V6" 1)

echo "Rule at Position 1 (IPv4): $FIRST_RULE_V4"
echo "Rule at Position 1 (IPv6): $FIRST_RULE_V6"

if echo "$FIRST_RULE_V4" | grep -Fq -- "$TAG" && echo "$FIRST_RULE_V6" | grep -Fq -- "$TAG"; then
    echo "PASS: Trial rules are confirmed strictly at Position 1 in both IPv4 and IPv6."
else
    echo "FAIL: Trial rules are not at Position 1!"
    exit 1
fi

# Verify total count increased by exactly 1
CURRENT_COUNT_V4=$(sudo iptables -S "$CHAIN_V4" | grep -c '^-A')
CURRENT_COUNT_V6=$(sudo ip6tables -S "$CHAIN_V6" | grep -c '^-A')
if [ "$CURRENT_COUNT_V4" -eq "$((INITIAL_COUNT_V4 + 1))" ] && [ "$CURRENT_COUNT_V6" -eq "$((INITIAL_COUNT_V6 + 1))" ]; then
    echo "PASS: Exactly 1 rule added per protocol family."
else
    echo "FAIL: Unexpected rule count after apply."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 2: Duplicate Apply Rejection
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Duplicate Apply Rejection ---"
if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" apply "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Helper allowed duplicate apply with the same tag!"
    exit 1
else
    echo "PASS: Duplicate apply correctly rejected."
fi

# Confirm rule counts have not increased
DUP_COUNT_V4=$(sudo iptables -S "$CHAIN_V4" | grep -c '^-A')
DUP_COUNT_V6=$(sudo ip6tables -S "$CHAIN_V6" | grep -c '^-A')
if [ "$DUP_COUNT_V4" -eq "$CURRENT_COUNT_V4" ] && [ "$DUP_COUNT_V6" -eq "$CURRENT_COUNT_V6" ]; then
    echo "PASS: Rule counts unchanged after duplicate apply rejection."
else
    echo "FAIL: Rule counts drifted after duplicate apply rejection!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 3: CLI check_position Functionality
# -----------------------------------------------------------------------------
echo "--- [TEST 3] CLI check_position Functionality ---"
if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" check_position ipv4 "$CHAIN_V4" "$TAG" 1 && \
   IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" check_position ipv6 "$CHAIN_V6" "$TAG" 1; then
    echo "PASS: check_position succeeded for position 1."
else
    echo "FAIL: check_position failed for position 1!"
    exit 1
fi

if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" check_position ipv4 "$CHAIN_V4" "$TAG" 2 2>/dev/null; then
    echo "FAIL: check_position falsely succeeded for position 2!"
    exit 1
else
    echo "PASS: check_position correctly rejected wrong position 2."
fi

# -----------------------------------------------------------------------------
# TEST 4: Targeted Rollback Preserves Pre-Existing Un-Commented Rules
# -----------------------------------------------------------------------------
echo "--- [TEST 4] Production Helper Rollback & Rule Preservation ---"
IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
  sh "$HELPER" rollback "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG"

# Verify trial rule is gone
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Tagged trial rule still present in IPv4 after rollback!"
    exit 1
fi
if sudo ip6tables -C "$CHAIN_V6" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Tagged trial rule still present in IPv6 after rollback!"
    exit 1
fi

# CRUCIAL ASSERTION: Verify pre-existing un-commented DROP rule on port 56789 STILL EXISTS!
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
    echo "PASS: Pre-existing un-commented IPv4 DROP rule on port $PORT was PRESERVED."
else
    echo "FAIL: Pre-existing IPv4 rule was wiped out!"
    exit 1
fi

if sudo ip6tables -C "$CHAIN_V6" -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
    echo "PASS: Pre-existing un-commented IPv6 DROP rule on port $PORT was PRESERVED."
else
    echo "FAIL: Pre-existing IPv6 rule was wiped out!"
    exit 1
fi

# Verify rule counts returned exactly to initial counts
FINAL_COUNT_V4=$(sudo iptables -S "$CHAIN_V4" | grep -c '^-A')
FINAL_COUNT_V6=$(sudo ip6tables -S "$CHAIN_V6" | grep -c '^-A')
if [ "$FINAL_COUNT_V4" -eq "$INITIAL_COUNT_V4" ] && [ "$FINAL_COUNT_V6" -eq "$INITIAL_COUNT_V6" ]; then
    echo "PASS: Netfilter chains returned precisely to baseline counts (zero side-effects)."
else
    echo "FAIL: Netfilter counts drift detected after rollback."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 5: Idempotent Rollback Execution (Second Call)
# -----------------------------------------------------------------------------
echo "--- [TEST 5] Idempotent Rollback Execution (Second Call) ---"
if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" rollback "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG"; then
    echo "PASS: Second rollback call succeeded cleanly without error."
else
    echo "FAIL: Second rollback call failed!"
    exit 1
fi

# Verify baseline rules still preserved
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -j DROP 2>/dev/null && \
   sudo ip6tables -C "$CHAIN_V6" -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
    echo "PASS: Baseline rules still intact after second rollback."
else
    echo "FAIL: Baseline rules damaged during second rollback!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 6: Failure Injection – IPv6 Insertion Fails AFTER IPv4 Insertion Succeeded
# -----------------------------------------------------------------------------
echo "--- [TEST 6] Failure Injection: IPv6 Insertion Fails AFTER IPv4 Succeeded ---"
# We create a mock ip6tables wrapper where -L and -S succeed, but -I fails!
MOCK_IP6="${TMP_DIR}/mock_ip6tables_fail_insert.sh"
cat << 'EOF' > "$MOCK_IP6"
#!/bin/sh
# Fail only when inserting rule (-I)
if [ "$1" = "-I" ]; then
    echo "[SIMULATED_FAILURE] Simulated IPv6 insertion failure" >&2
    exit 42
fi
exec sudo ip6tables "$@"
EOF
chmod +x "$MOCK_IP6"

# Run apply: IPv4 will insert, then IPv6 will fail
if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="$MOCK_IP6" \
   sh "$HELPER" apply "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Helper succeeded despite IPv6 insertion failure!"
    exit 1
else
    echo "PASS: Helper correctly reported failure when IPv6 insertion failed."
fi

# Verify IPv4 trial rule was NOT left behind (atomic rollback restored baseline)
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Atomic rollback left orphaned IPv4 trial rule behind!"
    exit 1
else
    echo "PASS: Atomic rollback cleanly eliminated IPv4 trial rule after IPv6 insertion failure."
fi

# Verify baseline rules remain intact
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
    echo "PASS: Baseline IPv4 rule preserved across atomic rollback."
else
    echo "FAIL: Baseline rule damaged during atomic rollback!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 7: Failure Injection – IPv4 Rollback Fails (Catastrophic Recovery Failure)
# -----------------------------------------------------------------------------
echo "--- [TEST 7] Failure Injection: IPv4 Deletion Fails During Atomic Rollback ---"
# Wrapper where iptables -D fails, simulating inability to delete IPv4 rule
MOCK_IPTABLES_FAIL_DEL="${TMP_DIR}/mock_iptables_fail_del.sh"
cat << 'EOF' > "$MOCK_IPTABLES_FAIL_DEL"
#!/bin/sh
if [ "$1" = "-D" ]; then
    echo "[SIMULATED_FAILURE] Simulated iptables deletion failure" >&2
    exit 55
fi
exec sudo iptables "$@"
EOF
chmod +x "$MOCK_IPTABLES_FAIL_DEL"

# Apply with failing IPv6 insertion AND failing IPv4 deletion
if IPTABLES_CMD="$MOCK_IPTABLES_FAIL_DEL" IP6TABLES_CMD="$MOCK_IP6" \
   sh "$HELPER" apply "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Helper succeeded despite dual failures!"
    exit 1
else
    HELPER_EXIT=$?
    if [ "$HELPER_EXIT" -eq 2 ]; then
        echo "PASS: Helper correctly returned critical code 2 (ROLLBACK_FAILED) when IPv4 deletion failed."
    else
        echo "FAIL: Helper returned exit code $HELPER_EXIT instead of 2."
        exit 1
    fi
fi

# Manual cleanup of orphaned rule created in Test 7
sudo iptables -D "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null || true

# -----------------------------------------------------------------------------
# TEST 8: Missing Chain Detection During Rollback
# -----------------------------------------------------------------------------
echo "--- [TEST 8] Missing Chain Detection During Rollback ---"
if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" rollback "NON_EXISTENT_CHAIN_$$" "$CHAIN_V6" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Rollback succeeded despite non-existent chain!"
    exit 1
else
    RET_CODE=$?
    if [ "$RET_CODE" -eq 2 ]; then
        echo "PASS: Rollback correctly aborted with code 2 on missing chain."
    else
        echo "FAIL: Expected code 2 on missing chain, got $RET_CODE."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# TEST 9: Command Execution Error During Inspection (rule_exists returns 2)
# -----------------------------------------------------------------------------
echo "--- [TEST 9] Command Execution Failure Detection ---"
if IPTABLES_CMD="/bin/false" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" rollback "$CHAIN_V4" "$CHAIN_V6" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Rollback reported success despite failing iptables command!"
    exit 1
else
    echo "PASS: Rollback correctly reported error when iptables command failed."
fi

echo "=== ALL 9 FIREWALL OWNERSHIP & TRANSACTIONAL TESTS PASSED ==="
