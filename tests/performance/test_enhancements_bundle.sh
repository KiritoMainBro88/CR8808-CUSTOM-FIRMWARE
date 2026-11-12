#!/bin/sh
# tests/performance/test_enhancements_bundle.sh
# ==============================================================================
# Comprehensive Verification Harness for Modular RA82 Enhancement System
# Workstream B, D & F: Modern Userspace & Automated Optimization System
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53)
#
# Validates:
#   1. CLI operations & module listing.
#   2. Mode 1: --volatile installation (100% in RAM /tmp, zero flash writes).
#   3. Mode 1: --volatile uninstallation (full baseline restoration).
#   4. Mode 2: --persistent safety gate (requires --confirm-persistent).
#   5. Mode 2: --persistent installation & /data/auto_run.sh hook integration.
#   6. Mode 2: Startup script execution & auto-run persistence check.
#   7. Mode 2: --persistent uninstallation & clean hook removal.
#   8. Selective module installation (--modules module_rps,module_napi).
#   9. wg0 production protection (guaranteeing wg0 is never touched).
#
# Executed 100% in PC/WSL2 hermetic mock environment. Zero router writes.
# ==============================================================================

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="${REPO_ROOT}/enhancements/installer.sh"

MOCK_DIR="$(mktemp -d /tmp/ra82_enhance_mock.XXXXXX)"
export MOCK_ROOT="$MOCK_DIR"

cleanup() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "================================================================================"
echo ">>> RUNNING MODULAR RA82 ENHANCEMENT SYSTEM TEST HARNESS"
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

    # Sysfs: eth0 queues
    mkdir -p "$MOCK_DIR/sys/class/net/eth0/queues/rx-0"
    printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"

    # Sysctl: proc sys net core & ipv4 & netfilter
    mkdir -p "$MOCK_DIR/proc/sys/net/core"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/core/rps_sock_flow_entries"
    printf '10000\n' > "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog"
    printf '300\n' > "$MOCK_DIR/proc/sys/net/core/netdev_budget"

    mkdir -p "$MOCK_DIR/proc/sys/net/ipv4"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_tw_reuse"
    printf '60\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fin_timeout"

    mkdir -p "$MOCK_DIR/proc/sys/net/netfilter"
    printf '432000\n' > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"

    # Tmp & Data dirs
    mkdir -p "$MOCK_DIR/tmp" "$MOCK_DIR/data"
}

# ------------------------------------------------------------------------------
# TEST 1: CLI Discovery & Module Listing
# ------------------------------------------------------------------------------
echo "--- TEST 1: CLI Discovery & Listing ---"
init_mock_environment

_list_out=$(sh "$INSTALLER" list)
assert_eq "List includes module_rps" "1" "$(echo "$_list_out" | grep -q "module_rps" && echo 1 || echo 0)"
assert_eq "List includes module_napi" "1" "$(echo "$_list_out" | grep -q "module_napi" && echo 1 || echo 0)"
assert_eq "List includes module_sysctl" "1" "$(echo "$_list_out" | grep -q "module_sysctl" && echo 1 || echo 0)"
assert_eq "List includes module_wireguard" "1" "$(echo "$_list_out" | grep -q "module_wireguard" && echo 1 || echo 0)"

# ------------------------------------------------------------------------------
# TEST 2: Mode 1: --volatile Installation (100% RAM /tmp, zero flash writes)
# ------------------------------------------------------------------------------
echo "--- TEST 2: Mode 1: --volatile Installation ---"
init_mock_environment

sh "$INSTALLER" --volatile install >/dev/null 2>&1
assert_eq "Volatile manifest created in /tmp" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/manifest.json" ] && echo 1 || echo 0)"
assert_eq "Mode recorded as volatile" "1" "$(grep -q '"mode": "volatile"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"
assert_eq "Zero files created in /data (flash untouched)" "0" "$(ls -A "$MOCK_DIR/data" | wc -l | tr -d ' ')"

# Verify applied parameters
_eth0_rps=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "eth0 rps_cpus set to 2" "2" "$_eth0_rps"

_netdev_backlog=$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')
assert_eq "netdev_max_backlog set to 16384" "16384" "$_netdev_backlog"

_tcp_fastopen=$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen" | tr -d ' \t\r\n')
assert_eq "tcp_fastopen set to 3" "3" "$_tcp_fastopen"

_conntrack=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "conntrack timeout set to 86400" "86400" "$_conntrack"

assert_eq "wg1 test template deployed" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/wireguard/wg1_template.conf" ] && echo 1 || echo 0)"
assert_eq "Production wg0 untouched (no wg0.conf)" "0" "$([ -f "$MOCK_DIR/tmp/enhancements/wireguard/wg0.conf" ] && echo 1 || echo 0)"

# Verify command returns 0
sh "$INSTALLER" --volatile verify >/dev/null 2>&1
assert_eq "Volatile verification passed" "0" "$?"

# ------------------------------------------------------------------------------
# TEST 3: Mode 1: --volatile Uninstallation (Full Baseline Restoration)
# ------------------------------------------------------------------------------
echo "--- TEST 3: Mode 1: --volatile Uninstallation ---"

sh "$INSTALLER" --volatile uninstall >/dev/null 2>&1
assert_eq "Volatile directory purged" "0" "$([ ! -d "$MOCK_DIR/tmp/enhancements" ] && echo 0 || echo 1)"

_eth0_rps_reverted=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "eth0 rps_cpus restored to 0" "0" "$_eth0_rps_reverted"

_netdev_backlog_reverted=$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')
assert_eq "netdev_max_backlog restored to 10000" "10000" "$_netdev_backlog_reverted"

_tcp_fastopen_reverted=$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen" | tr -d ' \t\r\n')
assert_eq "tcp_fastopen restored to 0" "0" "$_tcp_fastopen_reverted"

_conntrack_reverted=$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')
assert_eq "conntrack timeout restored to 432000" "432000" "$_conntrack_reverted"

# ------------------------------------------------------------------------------
# TEST 4: Mode 2: --persistent Safety Gate Enforcement
# ------------------------------------------------------------------------------
echo "--- TEST 4: Mode 2: --persistent Safety Gate Enforcement ---"
init_mock_environment

if sh "$INSTALLER" --persistent install >/dev/null 2>&1; then
    echo "  [FAIL] Installer should have rejected persistent install without confirmation flag"
    FAILED=$((FAILED + 1))
    exit 1
else
    echo "  [PASS] Installer cleanly blocked persistent install without --confirm-persistent"
    PASSED=$((PASSED + 1))
fi

assert_eq "No enhancements created in /data" "0" "$([ ! -d "$MOCK_DIR/data/enhancements" ] && echo 0 || echo 1)"
assert_eq "No auto_run.sh created" "0" "$([ ! -f "$MOCK_DIR/data/auto_run.sh" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 5: Mode 2: --persistent Installation & Hook Integration
# ------------------------------------------------------------------------------
echo "--- TEST 5: Mode 2: --persistent Installation & Hook Integration ---"
init_mock_environment

sh "$INSTALLER" --persistent --confirm-persistent install >/dev/null 2>&1
assert_eq "Persistent manifest created in /data" "1" "$([ -f "$MOCK_DIR/data/enhancements/manifest.json" ] && echo 1 || echo 0)"
assert_eq "Mode recorded as persistent" "1" "$(grep -q '"mode": "persistent"' "$MOCK_DIR/data/enhancements/manifest.json" && echo 1 || echo 0)"
assert_eq "Persistent auto_run.sh created" "1" "$([ -f "$MOCK_DIR/data/auto_run.sh" ] && echo 1 || echo 0)"
assert_eq "auto_run.sh contains hook" "1" "$(grep -q "BEGIN RA82 ENHANCEMENTS HOOK" "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"
assert_eq "auto_run.sh checks SAFE_MODE" "1" "$(grep -q "SAFE_MODE" "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"

sh "$INSTALLER" --persistent verify >/dev/null 2>&1
assert_eq "Persistent verification passed" "0" "$?"

# ------------------------------------------------------------------------------
# TEST 6: Mode 2: Startup Hook Execution Simulation
# ------------------------------------------------------------------------------
echo "--- TEST 6: Mode 2: Startup Hook Execution Simulation ---"
# Reset kernel parameters to baseline to simulate a fresh reboot
printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
printf '10000\n' > "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog"

# Execute startup script
sh "$MOCK_DIR/data/enhancements/bin/auto_enhancements.sh" start >/dev/null 2>&1

_eth0_after_boot=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "Startup hook re-applied rps_cpus=2" "2" "$_eth0_after_boot"

_backlog_after_boot=$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')
assert_eq "Startup hook re-applied netdev_max_backlog=16384" "16384" "$_backlog_after_boot"

# ------------------------------------------------------------------------------
# TEST 7: Mode 2: --persistent Uninstallation & Clean Hook Removal
# ------------------------------------------------------------------------------
echo "--- TEST 7: Mode 2: --persistent Uninstallation ---"

sh "$INSTALLER" --persistent uninstall >/dev/null 2>&1
assert_eq "Persistent directory purged" "0" "$([ ! -d "$MOCK_DIR/data/enhancements" ] && echo 0 || echo 1)"
assert_eq "auto_run.sh hook stripped" "0" "$([ -f "$MOCK_DIR/data/auto_run.sh" ] && grep -q "BEGIN RA82 ENHANCEMENTS HOOK" "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"

_eth0_rps_restored=$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')
assert_eq "eth0 rps_cpus restored to 0" "0" "$_eth0_rps_restored"

# ------------------------------------------------------------------------------
# TEST 8: Selective Module Installation
# ------------------------------------------------------------------------------
echo "--- TEST 8: Selective Module Installation ---"
init_mock_environment

sh "$INSTALLER" --volatile --modules module_rps,module_napi install >/dev/null 2>&1
assert_eq "module_rps installed" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/modules/module_rps.sh" ] && echo 1 || echo 0)"
assert_eq "module_napi installed" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/modules/module_napi.sh" ] && echo 1 || echo 0)"
assert_eq "module_sysctl NOT installed" "0" "$([ -f "$MOCK_DIR/tmp/enhancements/modules/module_sysctl.sh" ] && echo 1 || echo 0)"
assert_eq "module_wireguard NOT installed" "0" "$([ -f "$MOCK_DIR/tmp/enhancements/modules/module_wireguard.sh" ] && echo 1 || echo 0)"

assert_eq "eth0 rps_cpus set to 2" "2" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "netdev_max_backlog set to 16384" "16384" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')"
assert_eq "tcp_fastopen remained at baseline 0" "0" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen" | tr -d ' \t\r\n')"

sh "$INSTALLER" --volatile uninstall >/dev/null 2>&1
assert_eq "Volatile directory purged after selective test" "0" "$([ ! -d "$MOCK_DIR/tmp/enhancements" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST SUMMARY
# ------------------------------------------------------------------------------
echo "================================================================================"
echo "ENHANCEMENTS BUNDLE TEST COMPLETE: $PASSED assertions passed, $FAILED assertions failed."
echo "================================================================================"

if [ "$FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
