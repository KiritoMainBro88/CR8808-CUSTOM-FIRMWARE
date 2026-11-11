#!/bin/sh
# tests/test_firewall_ownership.sh
# Empirical Test Harness for Firewall Rule Ownership, Position 1 Verification,
# Production Helper Integration, and Dynamic Chain Isolation.
# Executed via real Linux netfilter in WSL2.

set -e

# Generate unique, non-colliding dynamic chain names for this specific test PID
UNIQUE_SUFFIX="$$-${RANDOM:-12345}"
CHAIN_V4="M11_V4_${UNIQUE_SUFFIX}"
CHAIN_V6="M11_V6_${UNIQUE_SUFFIX}"
TAG="M11_1_TRIAL_SSH_BLOCK"
PORT="56789"
HELPER="scripts/firewall_manager.sh"

echo "=== M11.1.0.3 FIREWALL OWNERSHIP & PRODUCTION HELPER TEST ==="
echo "Dynamic Test Chains: $CHAIN_V4 (IPv4), $CHAIN_V6 (IPv6)"

# Selective cleanup function: ONLY removes chains created by this run
cleanup() {
    echo "Cleaning up dynamic test chains ($CHAIN_V4, $CHAIN_V6)..."
    sudo iptables -F "$CHAIN_V4" 2>/dev/null || true
    sudo iptables -X "$CHAIN_V4" 2>/dev/null || true
    sudo ip6tables -F "$CHAIN_V6" 2>/dev/null || true
    sudo ip6tables -X "$CHAIN_V6" 2>/dev/null || true
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# SETUP: Create isolated dynamic test chains representing zone_wan_input
# -----------------------------------------------------------------------------
sudo iptables -N "$CHAIN_V4"
sudo ip6tables -N "$CHAIN_V6"

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
# TEST 2: Targeted Rollback Preserves Pre-Existing Un-Commented Rules
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Production Helper Rollback & Rule Preservation ---"
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
# TEST 3: Atomic Transactional Rollback on Simulated IPv6 Failure
# -----------------------------------------------------------------------------
echo "--- [TEST 3] Atomic Rollback on Partial (IPv6) Failure ---"
# We simulate IPv6 failure by directing IPv6 to a non-existent chain
INVALID_CHAIN="NON_EXISTENT_CHAIN_$$"

if IPTABLES_CMD="sudo iptables" IP6TABLES_CMD="sudo ip6tables" \
   sh "$HELPER" apply "$CHAIN_V4" "$INVALID_CHAIN" "$PORT" "$TAG" 2>/dev/null; then
    echo "FAIL: Helper succeeded despite invalid IPv6 chain!"
    exit 1
else
    echo "PASS: Helper correctly reported error on IPv6 chain failure."
fi

# Verify IPv4 trial rule was NOT left behind (atomic rollback restored baseline)
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Atomic rollback left orphaned IPv4 trial rule behind!"
    exit 1
else
    echo "PASS: Atomic rollback cleanly reverted IPv4 trial rule after IPv6 failure."
fi

# Verify baseline rules are still intact
if sudo iptables -C "$CHAIN_V4" -p tcp --dport "$PORT" -j DROP 2>/dev/null; then
    echo "PASS: Baseline rules remained intact through atomic rollback."
else
    echo "FAIL: Baseline rules damaged during atomic rollback."
    exit 1
fi

echo "=== ALL 3 FIREWALL OWNERSHIP & HELPER TESTS PASSED ==="
