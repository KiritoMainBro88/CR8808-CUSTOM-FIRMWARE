#!/bin/sh
# tests/performance/test_optimization_framework.sh
# ==============================================================================
# Comprehensive Test Harness for RA82 Modular Optimization Framework
# Workstream G: Automated Optimization Framework
#
# Validates:
#   1. Isolated mock root environment initialization (matching RA82 baseline).
#   2. CLI commands: list, audit, apply, rollback, rollback_all, verify.
#   3. Atomic apply, state snapshot creation, and verification for each profile
#      (including new dns_stability and enhanced nss_flow_tuning).
#   4. Bit-for-bit exact value restoration on rollback for every profile.
#   5. Multi-profile bulk apply and reverse-order rollback_all.
#   6. Fault injection and automatic instantaneous rollback on verification failure.
#   7. Lock contention and state consistency.
# ==============================================================================

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMEWORK="${REPO_ROOT}/performance/framework.sh"
PROFILES_DIR="${REPO_ROOT}/performance/profiles"

MOCK_DIR="$(mktemp -d /tmp/ra82_perf_mock.XXXXXX)"
export MOCK_ROOT="$MOCK_DIR"
export STATE_DIR="/tmp/perf_state"

cleanup() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "================================================================================"
echo ">>> RUNNING RA82 OPTIMIZATION FRAMEWORK TEST HARNESS"
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

# ------------------------------------------------------------------------------
# STEP 0: Initialize Mock Procfs and Sysfs matching Xiaomi RA82 Factory Defaults
# ------------------------------------------------------------------------------
echo "--- Initializing Synthetic RA82 Baseline Environment ---"

init_mock_tree() {
    rm -rf "${MOCK_DIR:?}"/*

    # Sysctl: Network Core & Backlog
    mkdir -p "$MOCK_DIR/proc/sys/net/core"
    printf '%s\n' "10000" > "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog"
    printf '%s\n' "300" > "$MOCK_DIR/proc/sys/net/core/netdev_budget"
    printf '%s\n' "2000" > "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs"
    printf '%s\n' "2097152" > "$MOCK_DIR/proc/sys/net/core/rmem_max"
    printf '%s\n' "2097152" > "$MOCK_DIR/proc/sys/net/core/wmem_max"
    printf '%s\n' "pfifo_fast" > "$MOCK_DIR/proc/sys/net/core/default_qdisc"
    printf '%s\n' "0" > "$MOCK_DIR/proc/sys/net/core/rps_sock_flow_entries"

    # Sysctl: TCP
    mkdir -p "$MOCK_DIR/proc/sys/net/ipv4"
    printf '%s\n' "cubic" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_congestion_control"
    printf '%s\n' "cubic reno" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_available_congestion_control"
    printf '%s\n' "4096 524288 4194304" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_rmem"
    printf '%s\n' "4096 524288 4194304" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_wmem"
    printf '%s\n' "0" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen"
    printf '%s\n' "0" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_tw_reuse"
    printf '%s\n' "60" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fin_timeout"
    printf '%s\n' "1024" > "$MOCK_DIR/proc/sys/net/ipv4/tcp_max_syn_backlog"

    # Sysctl: Netfilter Conntrack
    mkdir -p "$MOCK_DIR/proc/sys/net/netfilter"
    printf '%s\n' "16384" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_max"
    printf '%s\n' "432000" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"
    printf '%s\n' "60" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait"
    printf '%s\n' "120" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait"
    printf '%s\n' "120" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait"
    printf '%s\n' "180" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream"
    printf '%s\n' "600" > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_generic_timeout"

    # Sysctl: Qualcomm NSS
    mkdir -p "$MOCK_DIR/proc/sys/net/nss/general"
    printf '%s\n' "1" > "$MOCK_DIR/proc/sys/net/nss/general/redirect"

    # Sysfs: ECM Module
    mkdir -p "$MOCK_DIR/sys/module/ecm/parameters"
    printf '%s\n' "0" > "$MOCK_DIR/sys/module/ecm/parameters/accel_delay_pkts"
    printf '%s\n' "0" > "$MOCK_DIR/sys/module/ecm/parameters/auto_bypassed"

    # Sysfs: Network Interfaces & RPS Queues
    for iface in eth0 eth1 br-lan wg0; do
        mkdir -p "$MOCK_DIR/sys/class/net/${iface}/queues/rx-0"
        printf '%s\n' "0" > "$MOCK_DIR/sys/class/net/${iface}/queues/rx-0/rps_cpus"
        printf '%s\n' "0" > "$MOCK_DIR/sys/class/net/${iface}/queues/rx-0/rps_flow_cnt"
    done

    # Procfs: Interrupts & smp_affinity
    mkdir -p "$MOCK_DIR/proc"
    cat << 'EOF' > "$MOCK_DIR/proc/interrupts"
           CPU0       CPU1       
 28:  203457809          0       GIC 431 Edge      nss_queue0
 29:          0     752612       GIC 430 Edge      nss_queue1
 41:    9353079          0       GIC 326 Edge      ce2
 91:   21405881          0       GIC 449 Edge      pci0_wlan_ce_1
 92:    8326409          0       GIC 450 Edge      pci0_wlan_ce_2
 98:    6099865          0       GIC 456 Edge      pci0_wlan_grp_dp_3
EOF

    for irq in 28 29 41 91 92 98; do
        mkdir -p "$MOCK_DIR/proc/irq/${irq}"
        if [ "$irq" = "29" ]; then
            printf '%s\n' "2" > "$MOCK_DIR/proc/irq/${irq}/smp_affinity"
        else
            printf '%s\n' "1" > "$MOCK_DIR/proc/irq/${irq}/smp_affinity"
        fi
    done

    # Configuration paths: dnsmasq
    mkdir -p "$MOCK_DIR/etc/dnsmasq.d"
    mkdir -p "$MOCK_DIR/tmp/resolv.conf.d"

    # State directory
    mkdir -p "$MOCK_DIR$STATE_DIR"
}

init_mock_tree
echo "Baseline initialized successfully."

# ------------------------------------------------------------------------------
# TEST 1: Framework Discovery & CLI Commands
# ------------------------------------------------------------------------------
echo "--- TEST 1: Framework Discovery & CLI Operations ---"

# Test 'list' command
LIST_OUT=$(sh "$FRAMEWORK" list)
echo "$LIST_OUT" | grep -q "conntrack_tuning"
assert_eq "Framework lists conntrack_tuning" "0" "$?"
echo "$LIST_OUT" | grep -q "dns_stability"
assert_eq "Framework lists dns_stability" "0" "$?"
echo "$LIST_OUT" | grep -q "rps_rfs_tuning"
assert_eq "Framework lists rps_rfs_tuning" "0" "$?"
echo "$LIST_OUT" | grep -q "tcp_tuning"
assert_eq "Framework lists tcp_tuning" "0" "$?"
echo "$LIST_OUT" | grep -q "nss_flow_tuning"
assert_eq "Framework lists nss_flow_tuning" "0" "$?"

# Test 'audit' command
AUDIT_OUT=$(sh "$FRAMEWORK" audit dns_stability)
echo "$AUDIT_OUT" | grep -q "10-dns-stability.conf"
assert_eq "Framework audits dns_stability correctly" "0" "$?"

# ------------------------------------------------------------------------------
# TEST 2: Individual Profile Atomic Apply and Exact Verification
# ------------------------------------------------------------------------------
echo "--- TEST 2: Individual Profile Atomic Apply & State Capture ---"

PROFILES="rps_rfs_tuning irq_affinity netdev_backlog tcp_tuning qdisc_tuning conntrack_tuning nss_flow_tuning dns_stability"

for prof in $PROFILES; do
    echo "Testing Profile: $prof"
    sh "$FRAMEWORK" apply "$prof" >/dev/null 2>&1
    assert_eq "Profile $prof applied with exit code 0" "0" "$?"

    # Verify state snapshot file was created
    [ -f "$MOCK_DIR$STATE_DIR/${prof}.state" ]
    assert_eq "State snapshot exists for $prof" "0" "$?"

    # Verify framework registers profile as active
    grep -q "^${prof}$" "$MOCK_DIR$STATE_DIR/active_profiles.list"
    assert_eq "Active list contains $prof" "0" "$?"

    # Verify profile verify passes
    sh "$FRAMEWORK" verify "$prof" >/dev/null 2>&1
    assert_eq "Profile $prof verify passes" "0" "$?"
done

# Verify specific values modified by apply
assert_eq "net.core.rps_sock_flow_entries set to 16384" "16384" "$(cat "$MOCK_DIR/proc/sys/net/core/rps_sock_flow_entries")"
assert_eq "eth0 rps_cpus set to 2" "2" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus")"
assert_eq "IRQ 91 smp_affinity set to 2" "2" "$(cat "$MOCK_DIR/proc/irq/91/smp_affinity")"
assert_eq "netdev_max_backlog set to 16384" "16384" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog")"
assert_eq "netdev_budget set to 600" "600" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget")"
assert_eq "tcp_fastopen set to 3" "3" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen")"
assert_eq "tcp_tw_reuse set to 1" "1" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_tw_reuse")"
assert_eq "tcp_fin_timeout set to 30" "30" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fin_timeout")"
assert_eq "default_qdisc set to fq_codel" "fq_codel" "$(cat "$MOCK_DIR/proc/sys/net/core/default_qdisc")"
assert_eq "nf_conntrack_tcp_timeout_established set to 86400" "86400" "$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established")"
assert_eq "ecm accel_delay_pkts set to 4" "4" "$(cat "$MOCK_DIR/sys/module/ecm/parameters/accel_delay_pkts")"
assert_eq "ecm auto_bypassed set to 0" "0" "$(cat "$MOCK_DIR/sys/module/ecm/parameters/auto_bypassed")"

# Verify dns_stability snippet contents
grep -q "cache-size=2048" "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf"
assert_eq "dnsmasq cache-size set to 2048" "0" "$?"
grep -q "dns-forward-max=512" "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf"
assert_eq "dnsmasq dns-forward-max set to 512" "0" "$?"
grep -q "min-cache-ttl=300" "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf"
assert_eq "dnsmasq min-cache-ttl set to 300" "0" "$?"
grep -q "timeout:1" "$MOCK_DIR/tmp/resolv.conf.d/options.conf"
assert_eq "resolver options set to timeout:1" "0" "$?"

# Verify global verify
sh "$FRAMEWORK" verify >/dev/null 2>&1
assert_eq "Global verify confirms all active profiles" "0" "$?"

# ------------------------------------------------------------------------------
# TEST 3: Individual Profile Rollback & Bit-for-Bit Restoration
# ------------------------------------------------------------------------------
echo "--- TEST 3: Individual Profile Rollback & Bit-for-Bit Restoration ---"

# Rollback each profile in reverse order
for prof in dns_stability nss_flow_tuning conntrack_tuning qdisc_tuning tcp_tuning netdev_backlog irq_affinity rps_rfs_tuning; do
    sh "$FRAMEWORK" rollback "$prof" >/dev/null 2>&1
    assert_eq "Profile $prof rolled back with exit code 0" "0" "$?"

    # State file must be purged
    [ ! -f "$MOCK_DIR$STATE_DIR/${prof}.state" ]
    assert_eq "State file cleared for $prof" "0" "$?"

    # Active list must not contain prof
    if [ -f "$MOCK_DIR$STATE_DIR/active_profiles.list" ]; then
        ! grep -q "^${prof}$" "$MOCK_DIR$STATE_DIR/active_profiles.list"
        assert_eq "Active list purged of $prof" "0" "$?"
    fi
done

# Verify bit-for-bit restoration of factory values
assert_eq "net.core.rps_sock_flow_entries restored to 0" "0" "$(cat "$MOCK_DIR/proc/sys/net/core/rps_sock_flow_entries")"
assert_eq "eth0 rps_cpus restored to 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus")"
assert_eq "IRQ 91 smp_affinity restored to 1" "1" "$(cat "$MOCK_DIR/proc/irq/91/smp_affinity")"
assert_eq "netdev_max_backlog restored to 10000" "10000" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog")"
assert_eq "netdev_budget restored to 300" "300" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget")"
assert_eq "tcp_fastopen restored to 0" "0" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen")"
assert_eq "tcp_tw_reuse restored to 0" "0" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_tw_reuse")"
assert_eq "tcp_fin_timeout restored to 60" "60" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fin_timeout")"
assert_eq "default_qdisc restored to pfifo_fast" "pfifo_fast" "$(cat "$MOCK_DIR/proc/sys/net/core/default_qdisc")"
assert_eq "nf_conntrack_tcp_timeout_established restored to 432000" "432000" "$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established")"
assert_eq "ecm accel_delay_pkts restored to 0" "0" "$(cat "$MOCK_DIR/sys/module/ecm/parameters/accel_delay_pkts")"
assert_eq "dnsmasq snippet purged on rollback" "0" "$([ ! -f "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 4: Bulk Apply and rollback_all
# ------------------------------------------------------------------------------
echo "--- TEST 4: Multi-Profile Bulk Apply & rollback_all ---"

# Apply all profiles
for prof in $PROFILES; do
    sh "$FRAMEWORK" apply "$prof" >/dev/null 2>&1
done

assert_eq "tcp_fastopen is 3 after apply" "3" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen")"
assert_eq "netdev_budget is 600 after apply" "600" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget")"
assert_eq "dns snippet exists after bulk apply" "0" "$([ -f "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf" ] && echo 0 || echo 1)"

# Execute rollback_all
sh "$FRAMEWORK" rollback_all >/dev/null 2>&1
assert_eq "rollback_all exited with code 0" "0" "$?"

# Check all baseline values restored
assert_eq "netdev_budget restored to 300 via rollback_all" "300" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget")"
assert_eq "tcp_fastopen restored to 0 via rollback_all" "0" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen")"
assert_eq "default_qdisc restored to pfifo_fast via rollback_all" "pfifo_fast" "$(cat "$MOCK_DIR/proc/sys/net/core/default_qdisc")"
assert_eq "nf_conntrack_tcp_timeout_established restored to 432000 via rollback_all" "432000" "$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established")"
assert_eq "dnsmasq snippet purged via rollback_all" "0" "$([ ! -f "$MOCK_DIR/etc/dnsmasq.d/10-dns-stability.conf" ] && echo 0 || echo 1)"

# Active list should be empty
_active_count=$(sh "$FRAMEWORK" list | grep "Active Profiles Managed:" | cut -d':' -f2 | tr -d ' ')
assert_eq "Active profiles list is empty after rollback_all" "" "$_active_count"

# ------------------------------------------------------------------------------
# TEST 5: Fault Injection & Automatic Rollback on Verification Failure
# ------------------------------------------------------------------------------
echo "--- TEST 5: Fault Injection & Automatic Abort/Rollback ---"

init_mock_tree

# Simulate a hard write failure by replacing the sysctl file with a directory
rm -f "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen"
mkdir -p "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen"

# Attempt to apply tcp_tuning (must fail and automatically abort/rollback)
if sh "$FRAMEWORK" apply tcp_tuning >/dev/null 2>&1; then
    echo "  [FAIL] apply tcp_tuning should have failed on invalid sysctl file"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] apply tcp_tuning failed cleanly as expected"
    PASSED=$((PASSED + 1))
fi

# Assert tcp_tuning is NOT listed in active profiles
if [ -f "$MOCK_DIR$STATE_DIR/active_profiles.list" ]; then
    if grep -q "^tcp_tuning$" "$MOCK_DIR$STATE_DIR/active_profiles.list"; then
        echo "  [FAIL] Failed profile should not be in active list"
        FAILED=$((FAILED + 1))
        exit 1
    else
        echo "  [PASS] Failed profile was not registered in active list"
        PASSED=$((PASSED + 1))
    fi
else
    echo "  [PASS] Active profiles list does not exist (clean state)"
    PASSED=$((PASSED + 1))
fi

# Assert state file was cleaned up on failure
if [ -f "$MOCK_DIR$STATE_DIR/tcp_tuning.state" ]; then
    echo "  [FAIL] Orphaned state file should have been removed on abort"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] State file was cleaned up during automatic rollback"
    PASSED=$((PASSED + 1))
fi

# ------------------------------------------------------------------------------
# TEST 6: Concurrency Lock Verification
# ------------------------------------------------------------------------------
echo "--- TEST 6: Concurrency Lock Protection ---"

# Simulate an active external lock
mkdir -p "$MOCK_DIR$STATE_DIR/framework.lock.d"
echo "$$" > "$MOCK_DIR$STATE_DIR/framework.lock.d/pid"

# Attempt to apply profile while lock is held (should fail)
if sh "$FRAMEWORK" apply conntrack_tuning >/dev/null 2>&1; then
    echo "  [FAIL] apply should not succeed when lock is held"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Lock contention prevented concurrent execution"
    PASSED=$((PASSED + 1))
fi

# Release simulated lock
rm -rf "$MOCK_DIR$STATE_DIR/framework.lock.d"

# ------------------------------------------------------------------------------
# TEST SUMMARY
# ------------------------------------------------------------------------------
echo "================================================================================"
echo "TEST COMPLETE: $PASSED assertions passed, $FAILED assertions failed."
echo "================================================================================"

if [ "$FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
