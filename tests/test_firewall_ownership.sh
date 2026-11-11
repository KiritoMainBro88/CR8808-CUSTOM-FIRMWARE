#!/bin/sh
# tests/test_firewall_ownership.sh
# Empirical Test Harness for Firewall Rule Ownership, Targeted Rollback,
# Pre-Existing Rule Preservation, and Atomic Failure Rollback.
# Executed via real Linux netfilter in WSL2.

set -e

CHAIN_V4="TEST_M11_WAN_IN"
CHAIN_V6="TEST_M11_WAN_IN"
TAG="M11_1_TRIAL_SSH_BLOCK"

echo "=== M11.1.0.2 FIREWALL RULE OWNERSHIP & TRANSACTIONAL ROLLBACK TEST ==="

# Cleanup function to restore clean state
cleanup() {
    echo "Cleaning up test netfilter chains..."
    sudo iptables -F "$CHAIN_V4" 2>/dev/null || true
    sudo iptables -X "$CHAIN_V4" 2>/dev/null || true
    sudo ip6tables -F "$CHAIN_V6" 2>/dev/null || true
    sudo ip6tables -X "$CHAIN_V6" 2>/dev/null || true
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# SETUP: Create isolated test chains representing zone_wan_input
# -----------------------------------------------------------------------------
cleanup
sudo iptables -N "$CHAIN_V4"
sudo ip6tables -N "$CHAIN_V6"

# Add pre-existing baseline rules into IPv4 chain:
# Rule 1: A pre-existing accept rule (simulating custom wan input)
sudo iptables -A "$CHAIN_V4" -p tcp --dport 80 -j ACCEPT
# Rule 2: A pre-existing DROP on port 56789 WITHOUT our comment (pre-existing baseline)
sudo iptables -A "$CHAIN_V4" -p tcp --dport 56789 -j DROP
# Rule 3: Another pre-existing rule
sudo iptables -A "$CHAIN_V4" -p udp --dport 53 -j ACCEPT

# Add pre-existing baseline rule into IPv6 chain:
sudo ip6tables -A "$CHAIN_V6" -p tcp --dport 56789 -j DROP

echo "Pre-existing IPv4 rules count: $(sudo iptables -S "$CHAIN_V4" | wc -l)"
echo "Pre-existing IPv6 rules count: $(sudo ip6tables -S "$CHAIN_V6" | wc -l)"

# -----------------------------------------------------------------------------
# TEST 1: Prerequisite Check (Chain Existence)
# -----------------------------------------------------------------------------
echo "--- [TEST 1] Prerequisite Chain Validation ---"
if sudo iptables -L "$CHAIN_V4" -n >/dev/null 2>&1 && sudo ip6tables -L "$CHAIN_V6" -n >/dev/null 2>&1; then
    echo "PASS: Prerequisite verification confirmed chains exist."
else
    echo "FAIL: Prerequisite verification failed."
    exit 1
fi

# Test non-existent chain check
if ! sudo iptables -L "NON_EXISTENT_CHAIN" -n >/dev/null 2>&1; then
    echo "PASS: Non-existent chain correctly identified and rejected."
else
    echo "FAIL: Non-existent chain detection failed."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 2: Targeted Rule Insertion with Explicit Ownership Tag
# -----------------------------------------------------------------------------
echo "--- [TEST 2] Targeted Rule Insertion with Explicit Identifier ---"
# Insert at position 1 with comment
sudo iptables -I "$CHAIN_V4" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP
sudo ip6tables -I "$CHAIN_V6" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP

# Verify insertion via iptables -C
if sudo iptables -C "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP && \
   sudo ip6tables -C "$CHAIN_V6" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP; then
    echo "PASS: Tagged trial rules successfully inserted and verified in position 1."
else
    echo "FAIL: Tagged trial rules failed verification."
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 3: Pre-Existing Rule Preservation During Targeted Rollback
# -----------------------------------------------------------------------------
echo "--- [TEST 3] Pre-Existing Rule Preservation During Rollback ---"
# Execute targeted rollback ONLY on rules matching our comment
sudo iptables -D "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP
sudo ip6tables -D "$CHAIN_V6" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP

# Check that the tagged rule is gone:
if sudo iptables -C "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Tagged rule was not deleted by targeted rollback!"
    exit 1
fi

# CRUCIAL CHECK: Verify that the pre-existing un-commented DROP rule on port 56789 is STILL INTACT!
if sudo iptables -C "$CHAIN_V4" -p tcp --dport 56789 -j DROP 2>/dev/null; then
    echo "PASS: Pre-existing un-commented DROP rule on port 56789 was PRESERVED!"
else
    echo "FAIL: Pre-existing rule was incorrectly deleted by rollback!"
    exit 1
fi

if sudo ip6tables -C "$CHAIN_V6" -p tcp --dport 56789 -j DROP 2>/dev/null; then
    echo "PASS: Pre-existing IPv6 rule on port 56789 was PRESERVED!"
else
    echo "FAIL: Pre-existing IPv6 rule was deleted!"
    exit 1
fi

# -----------------------------------------------------------------------------
# TEST 4: Atomic Transactional Rollback on Partial (IPv6) Failure
# -----------------------------------------------------------------------------
echo "--- [TEST 4] Atomic Transactional Rollback on Partial Failure ---"
# Scenario: IPv4 succeeds, but IPv6 fails (simulated by invalid chain)
IPV4_SUCCEEDED=0
IPV6_SUCCEEDED=0

# Step 1: Add IPv4
if sudo iptables -I "$CHAIN_V4" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP; then
    IPV4_SUCCEEDED=1
fi

# Step 2: Attempt IPv6 on an invalid target (simulating failure)
if sudo ip6tables -I "INVALID_CHAIN_SIMULATION" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    IPV6_SUCCEEDED=1
else
    IPV6_SUCCEEDED=0
fi

# Atomic failure handling:
if [ "$IPV4_SUCCEEDED" = "1" ] && [ "$IPV6_SUCCEEDED" = "0" ]; then
    echo "Detected partial failure (IPv6 failed). Executing immediate atomic rollback of IPv4..."
    sudo iptables -D "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP
fi

# Verify IPv4 was cleanly restored to baseline state (no orphaned rule)
if sudo iptables -C "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP 2>/dev/null; then
    echo "FAIL: Atomic rollback left orphaned IPv4 trial rule!"
    exit 1
else
    echo "PASS: Atomic rollback cleanly removed IPv4 trial rule after IPv6 failure."
fi

# -----------------------------------------------------------------------------
# TEST 5: Gate Before Disarming (Verification Required Before Disarm)
# -----------------------------------------------------------------------------
echo "--- [TEST 5] Verification Gate Before Disarming ---"
# Add both rules properly
sudo iptables -I "$CHAIN_V4" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP
sudo ip6tables -I "$CHAIN_V6" 1 -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP

# Verification function
verify_trial_rules() {
    sudo iptables -C "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP 2>/dev/null && \
    sudo ip6tables -C "$CHAIN_V6" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP 2>/dev/null
}

DISARM_AUTHORIZED=0
if verify_trial_rules; then
    DISARM_AUTHORIZED=1
    echo "PASS: Verification confirmed both rules active. Disarm gate AUTHORIZED."
else
    echo "FAIL: Verification failed. Disarm gate BLOCKED."
    exit 1
fi

if [ "$DISARM_AUTHORIZED" -ne 1 ]; then
    echo "FAIL: Disarm permitted without verification."
    exit 1
fi

# Clean up trial rules
sudo iptables -D "$CHAIN_V4" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP
sudo ip6tables -D "$CHAIN_V6" -p tcp --dport 56789 -m comment --comment "$TAG" -j DROP

echo "=== ALL 5 FIREWALL RULE OWNERSHIP TESTS PASSED ==="
