#!/bin/sh
# tests/performance/test_enhancements_bundle.sh
# Comprehensive P0-2 Verification Harness for Modular RA82 Enhancement System
# Validates:
#   1. CLI list & read-only inspect (0 file/sysfs writes)
#   2. Separated 'stage' (copies files/manifest; 0 runtime parameter changes)
#   3. 'trial' safety gate (rejects without --authorize-trial)
#   4. '--authorize-trial' runtime apply + readback verification + optional nodes
#   5. 'rollback' restores all modified + optional params and removes state snapshots
#   6. 'uninstall' purges /tmp/enhancements cleanly and preserves unrelated /data/auto_run.sh
#   7. Disabled '--persistent' gate (unconditionally rejected in M12.6, 0 /data writes)
#   8. Partial write failure triggers atomic rollback of earlier writes
#   9. Missing snapshot refuses fabricated-default rollback
#  10. Incomplete rollback refuses uninstall directory purge (preserves state)
#  11. Production wg0 isolation & deprecated 'install' rejection

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
echo ">>> RUNNING P0-2 MODULAR RA82 ENHANCEMENT SYSTEM TEST HARNESS"
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

assert_fails() {
    _desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  [FAIL] $_desc (command succeeded unexpectedly)"
        FAILED=$((FAILED + 1))
        exit 1
    else
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    fi
}

init_mock_environment() {
    rm -rf "${MOCK_DIR:?}"/*

    mkdir -p "$MOCK_DIR/sys/class/net/eth0/queues/rx-0"
    mkdir -p "$MOCK_DIR/sys/class/net/eth1/queues/rx-0"
    mkdir -p "$MOCK_DIR/sys/class/net/br-lan/queues/rx-0"
    printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus"
    printf '0\n' > "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_flow_cnt"
    printf '0\n' > "$MOCK_DIR/sys/class/net/eth1/queues/rx-0/rps_cpus"
    printf '0\n' > "$MOCK_DIR/sys/class/net/br-lan/queues/rx-0/rps_cpus"

    mkdir -p "$MOCK_DIR/proc/sys/net/core"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/core/rps_sock_flow_entries"
    printf '10000\n' > "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog"
    printf '300\n' > "$MOCK_DIR/proc/sys/net/core/netdev_budget"
    printf '2000\n' > "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs"

    mkdir -p "$MOCK_DIR/proc/sys/net/ipv4"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen"
    printf '0\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_tw_reuse"
    printf '60\n' > "$MOCK_DIR/proc/sys/net/ipv4/tcp_fin_timeout"

    mkdir -p "$MOCK_DIR/proc/sys/net/netfilter"
    printf '432000\n' > "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established"

    mkdir -p "$MOCK_DIR/tmp" "$MOCK_DIR/data"
}

echo "--- TEST 1: CLI list & read-only inspect ---"
init_mock_environment
_list_out=$(sh "$INSTALLER" list)
assert_eq "List includes module_rps" "1" "$(echo "$_list_out" | grep -q "module_rps" && echo 1 || echo 0)"
assert_eq "List includes module_napi" "1" "$(echo "$_list_out" | grep -q "module_napi" && echo 1 || echo 0)"
assert_eq "List includes module_sysctl" "1" "$(echo "$_list_out" | grep -q "module_sysctl" && echo 1 || echo 0)"
assert_eq "List includes module_wireguard" "1" "$(echo "$_list_out" | grep -q "module_wireguard" && echo 1 || echo 0)"

sh "$INSTALLER" inspect >/dev/null 2>&1
assert_eq "Inspect exited 0" "0" "$?"
assert_eq "Inspect created 0 /tmp files" "0" "$([ ! -d "$MOCK_DIR/tmp/enhancements" ] && echo 0 || echo 1)"
assert_eq "Inspect left rps_cpus untouched" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"

echo "--- TEST 2: Separated stage does NOT mutate runtime parameters ---"
sh "$INSTALLER" --volatile stage >/dev/null 2>&1
assert_eq "Stage created manifest" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/manifest.json" ] && echo 1 || echo 0)"
assert_eq "Manifest trial_state is staged" "1" "$(grep -q '"trial_state": "staged"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"
assert_eq "Stage left eth0 rps_cpus at 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "Stage left netdev_max_backlog at 10000" "10000" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')"
assert_eq "Stage left wg0.conf absent" "0" "$([ ! -f "$MOCK_DIR/tmp/enhancements/wireguard/wg0.conf" ] && echo 0 || echo 1)"

echo "--- TEST 3: Safety gates (missing --authorize-trial, deprecated install, disabled --persistent) ---"
assert_fails "Trial rejected without --authorize-trial" sh "$INSTALLER" --volatile trial
assert_fails "Deprecated 'install' rejected" sh "$INSTALLER" --volatile install
assert_fails "--persistent rejected without confirmation" sh "$INSTALLER" --persistent stage
assert_fails "--persistent rejected even with --confirm-persistent" sh "$INSTALLER" --persistent --confirm-persistent stage
assert_eq "Zero files created in /data" "0" "$(ls -A "$MOCK_DIR/data" | wc -l | tr -d ' ')"

echo "--- TEST 4: Authorized Volatile Trial + Verify + Rollback + Optional Param Restore ---"
sh "$INSTALLER" --volatile --authorize-trial trial >/dev/null 2>&1
assert_eq "Manifest trial_state is trial_active" "1" "$(grep -q '"trial_state": "trial_active"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"
assert_eq "eth0 rps_cpus set to 2" "2" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "eth1 rps_cpus set to 3" "3" "$(cat "$MOCK_DIR/sys/class/net/eth1/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "eth0 rps_flow_cnt set to 4096" "4096" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_flow_cnt" | tr -d ' \t\r\n')"
assert_eq "netdev_max_backlog set to 16384" "16384" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')"
assert_eq "netdev_budget_usecs set to 4000" "4000" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs" | tr -d ' \t\r\n')"
assert_eq "tcp_fastopen set to 3" "3" "$(cat "$MOCK_DIR/proc/sys/net/ipv4/tcp_fastopen" | tr -d ' \t\r\n')"
assert_eq "conntrack timeout set to 86400" "86400" "$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')"

sh "$INSTALLER" --volatile verify >/dev/null 2>&1
assert_eq "Verify passed during active trial" "0" "$?"

sh "$INSTALLER" --volatile rollback >/dev/null 2>&1
assert_eq "Rollback restored eth0 rps_cpus to 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "Rollback restored eth1 rps_cpus to 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth1/queues/rx-0/rps_cpus" | tr -d ' \t\r\n')"
assert_eq "Rollback restored eth0 rps_flow_cnt to 0" "0" "$(cat "$MOCK_DIR/sys/class/net/eth0/queues/rx-0/rps_flow_cnt" | tr -d ' \t\r\n')"
assert_eq "Rollback restored netdev_budget_usecs to 2000" "2000" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs" | tr -d ' \t\r\n')"
assert_eq "Rollback restored conntrack timeout to 432000" "432000" "$(cat "$MOCK_DIR/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established" | tr -d ' \t\r\n')"
assert_eq "Manifest trial_state updated to rolled_back" "1" "$(grep -q '"trial_state": "rolled_back"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"

echo "--- TEST 5: Uninstall preserves unrelated /data/auto_run.sh lines ---"
cat << 'EOF' > "$MOCK_DIR/data/auto_run.sh"
#!/bin/sh
# User custom startup command
/data/custom_service start
# BEGIN RA82 ENHANCEMENTS HOOK
/data/enhancements/bin/auto_enhancements.sh start
# END RA82 ENHANCEMENTS HOOK
echo "after hook"
EOF

sh "$INSTALLER" --volatile uninstall >/dev/null 2>&1
assert_eq "Staged /tmp/enhancements purged on uninstall" "0" "$([ ! -d "$MOCK_DIR/tmp/enhancements" ] && echo 0 || echo 1)"
assert_eq "User /data/auto_run.sh preserved" "1" "$([ -f "$MOCK_DIR/data/auto_run.sh" ] && grep -q "/data/custom_service start" "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"
assert_eq "Trailing user line preserved" "1" "$(grep -q 'after hook' "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"
assert_eq "Hook marker removed cleanly" "0" "$(grep -q "BEGIN RA82 ENHANCEMENTS HOOK" "$MOCK_DIR/data/auto_run.sh" && echo 1 || echo 0)"

echo "--- TEST 6: Partial Write Failure & Atomic Recovery ---"
init_mock_environment
# Replace second required node (netdev_budget) with an unwritable directory so netdev_max_backlog applies first then fails!
rm -f "$MOCK_DIR/proc/sys/net/core/netdev_budget"
mkdir "$MOCK_DIR/proc/sys/net/core/netdev_budget"

assert_fails "Selective NAPI trial aborted on partial write error" sh "$INSTALLER" --volatile --authorize-trial --modules module_napi trial
assert_eq "First node netdev_max_backlog rolled back to 10000 on partial failure" "10000" "$(cat "$MOCK_DIR/proc/sys/net/core/netdev_max_backlog" | tr -d ' \t\r\n')"
assert_eq "Manifest marked rolled_back after atomic recovery" "1" "$(grep -q '"trial_state": "rolled_back"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"

echo "--- TEST 7: Missing Snapshot Refusal & Incomplete Rollback Uninstall Protection ---"
init_mock_environment
sh "$INSTALLER" --volatile --authorize-trial --modules module_rps,module_napi trial >/dev/null 2>&1

# Corrupt missing state snapshot test: remove module_rps state file
rm -f "$MOCK_DIR/tmp/enhancements/state/module_rps.state"
assert_fails "Rollback refused when active snapshot missing (no fabricated defaults)" sh "$INSTALLER" --volatile rollback
assert_eq "Uninstall refused to purge /tmp/enhancements on incomplete rollback" "1" "$(assert_fails_inner=0; sh "$INSTALLER" --volatile uninstall >/dev/null 2>&1 || assert_fails_inner=1; echo "$assert_fails_inner")"
assert_eq "Directory still present after refused uninstall" "1" "$([ -d "$MOCK_DIR/tmp/enhancements" ] && echo 1 || echo 0)"
assert_eq "Manifest reflects rollback_incomplete" "1" "$(grep -q '"trial_state": "rollback_incomplete"' "$MOCK_DIR/tmp/enhancements/manifest.json" && echo 1 || echo 0)"

# Restore state and also force write error during rollback of netdev_budget_usecs -> uninstall must STILL refuse!
init_mock_environment
sh "$INSTALLER" --volatile --authorize-trial --modules module_napi trial >/dev/null 2>&1
rm -f "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs"
mkdir "$MOCK_DIR/proc/sys/net/core/netdev_budget_usecs"
assert_fails "Uninstall aborted when optional node rollback write failed" sh "$INSTALLER" --volatile uninstall
assert_eq "State snapshot preserved after failed rollback" "1" "$([ -f "$MOCK_DIR/tmp/enhancements/state/module_napi.state" ] && echo 1 || echo 0)"
assert_eq "Enhancements directory preserved after failed rollback" "1" "$([ -d "$MOCK_DIR/tmp/enhancements" ] && echo 1 || echo 0)"

echo "================================================================================"
echo "P0-2 ENHANCEMENTS BUNDLE TEST COMPLETE: $PASSED assertions passed, $FAILED assertions failed."
echo "================================================================================"

[ "$FAILED" -eq 0 ]
