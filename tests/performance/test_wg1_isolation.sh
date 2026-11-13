#!/bin/sh
# tests/performance/test_wg1_isolation.sh
# P0-4 Hermetic Test Harness for BoringTun wg1 Isolation, Dry-Run, Manifest, & Teardown
# Runs 100% in PC/WSL2 mock environment with mocked ip/ss/proc/bin tools.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/performance/wireguard_rust/deploy_wg1.sh"
TEARDOWN_SCRIPT="${REPO_ROOT}/performance/wireguard_rust/teardown_wg1.sh"
BENCH_SCRIPT="${REPO_ROOT}/performance/wireguard_rust/benchmark_wg0_vs_wg1.sh"

TMP_ROOT="$(mktemp -d /tmp/wg1_iso_test.XXXXXX)"
MOCK_BIN="${TMP_ROOT}/mock_bin"
MOCK_NET="${TMP_ROOT}/mock_net"
MOCK_PROC="${TMP_ROOT}/mock_proc"
TEST_WG_DIR="${TMP_ROOT}/bin"
TEST_TMP_DIR="${TMP_ROOT}/tmp_wireguard"
TEST_SOCK_DIR="${TMP_ROOT}/var_run_wireguard"
TEST_PID_FILE="${TMP_ROOT}/wg1.pid"
TEST_LOG_FILE="${TMP_ROOT}/boringtun_wg1.log"
TEST_MANIFEST="${TMP_ROOT}/wg1_owned_manifest.env"
TEST_STAGED_SRC="${TMP_ROOT}/staged_boringtun-cli-armv7"

BG_PIDS=""
PASSED=0
FAILED=0

cleanup() {
    for _p in $BG_PIDS; do
        kill -9 "$_p" 2>/dev/null || true
    done
    if [ -f "$TEST_PID_FILE" ]; then
        _op=$(cat "$TEST_PID_FILE" 2>/dev/null || echo "")
        [ -n "$_op" ] && kill -9 "$_op" 2>/dev/null || true
    fi
    rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$MOCK_BIN" "$MOCK_NET/ifaces" "$MOCK_NET/routes" "$MOCK_NET/rules" "$MOCK_PROC/net"
: > "$MOCK_NET/routes/table_main"
: > "$MOCK_NET/routes/table_101"
: > "$MOCK_NET/rules/list"
printf 'sl local_address rem_address st\n' > "$MOCK_PROC/net/udp"

# Create mock ip tool tracking interfaces, addresses, routes, and rules atomically
cat << 'EOF' > "${MOCK_BIN}/ip"
#!/bin/sh
set -u
STATE="${MOCK_NET:?}"
mkdir -p "$STATE/ifaces" "$STATE/routes" "$STATE/rules"
touch "$STATE/rules/list" "$STATE/routes/table_101" "$STATE/routes/table_main"

sub="${1:-}"
shift || true
case "$sub" in
    link)
        op="${1:-}"; shift || true
        if [ "$op" = "show" ]; then
            if [ "${1:-}" = "dev" ]; then shift; fi
            dev="${1:-}"
            [ -n "$dev" ] && [ -d "$STATE/ifaces/$dev" ] || exit 1
            cat "$STATE/ifaces/$dev/link" 2>/dev/null || echo "$dev: <UP>"
            exit 0
        elif [ "$op" = "add" ]; then
            dev="$1"
            mkdir -p "$STATE/ifaces/$dev"
            echo "$dev: <DOWN>" > "$STATE/ifaces/$dev/link"
            exit 0
        elif [ "$op" = "set" ]; then
            while [ $# -gt 0 ]; do
                if [ "$1" = "dev" ]; then shift; dev="${1:-}"; break; fi
                shift
            done
            [ -n "${dev:-}" ] && [ -d "$STATE/ifaces/$dev" ] || exit 1
            echo "$dev: <UP,LOWER_UP> mtu 1420" > "$STATE/ifaces/$dev/link"
            exit 0
        elif [ "$op" = "del" ]; then
            if [ "${1:-}" = "dev" ]; then shift; fi
            dev="${1:-}"
            [ -n "$dev" ] && [ -d "$STATE/ifaces/$dev" ] || exit 1
            rm -rf "$STATE/ifaces/$dev"
            exit 0
        fi
        ;;
    addr)
        op="${1:-}"; shift || true
        if [ "$op" = "show" ]; then
            if [ "${1:-}" = "dev" ]; then
                shift; dev="${1:-}"
                [ -d "$STATE/ifaces/$dev" ] || exit 1
                cat "$STATE/ifaces/$dev/addr" 2>/dev/null || true
                exit 0
            fi
            for d in "$STATE/ifaces"/*; do
                [ -d "$d" ] && cat "$d/addr" 2>/dev/null || true
            done
            exit 0
        elif [ "$op" = "add" ]; then
            cidr="${1:-}"; shift || true
            if [ "${1:-}" = "dev" ]; then shift; fi
            dev="${1:-}"
            [ -d "$STATE/ifaces/$dev" ] || exit 1
            printf '    inet %s scope global %s\n' "$cidr" "$dev" >> "$STATE/ifaces/$dev/addr"
            exit 0
        fi
        ;;
    route)
        op="${1:-}"; shift || true
        tbl="main"
        args="$*"
        for tok in "$@"; do :; done
        # Parse optional table N
        _prev=""
        for tok in "$@"; do
            if [ "$_prev" = "table" ]; then tbl="$tok"; fi
            _prev="$tok"
        done
        tf="$STATE/routes/table_${tbl}"
        if [ "$op" = "show" ]; then
            [ -f "$tf" ] && cat "$tf" || true
            exit 0
        elif [ "$op" = "add" ]; then
            if [ "${MOCK_FAIL_IP_ROUTE_ADD:-0}" = "1" ]; then
                echo "mock ip route add injected failure" >&2
                exit 1
            fi
            subnet="${1:-}"
            dev=""
            _p=""
            for tok in "$@"; do
                if [ "$_p" = "dev" ]; then dev="$tok"; fi
                _p="$tok"
            done
            printf '%s dev %s table %s\n' "$subnet" "$dev" "$tbl" >> "$tf"
            exit 0
        elif [ "$op" = "del" ]; then
            subnet="${1:-}"
            dev=""
            _p=""
            for tok in "$@"; do
                if [ "$_p" = "dev" ]; then dev="$tok"; fi
                _p="$tok"
            done
            if [ -f "$tf" ]; then
                grep -vF "${subnet} dev ${dev} " "$tf" > "${tf}.tmp" 2>/dev/null || true
                mv "${tf}.tmp" "$tf"
            fi
            exit 0
        elif [ "$op" = "flush" ]; then
            : > "$tf"
            exit 0
        fi
        ;;
    rule)
        op="${1:-}"; shift || true
        rf="$STATE/rules/list"
        if [ "$op" = "show" ]; then
            cat "$rf" 2>/dev/null || true
            exit 0
        elif [ "$op" = "add" ]; then
            if [ "${MOCK_FAIL_IP_RULE_ADD:-0}" = "1" ]; then
                echo "mock ip rule add injected failure" >&2
                exit 1
            fi
            # expect: from <subnet> table <tbl>
            subnet="${2:-}"
            tbl="${4:-}"
            printf '32765:  from %s lookup %s\n' "$subnet" "$tbl" >> "$rf"
            exit 0
        elif [ "$op" = "del" ]; then
            subnet="${2:-}"
            tbl="${4:-}"
            if [ -f "$rf" ]; then
                grep -vF "from ${subnet} lookup ${tbl}" "$rf" > "${rf}.tmp" 2>/dev/null || true
                mv "${rf}.tmp" "$rf"
            fi
            exit 0
        fi
        ;;
esac
exit 1
EOF
chmod +x "${MOCK_BIN}/ip"

# Mock ss and netstat & pidof & ping
cat << 'EOF' > "${MOCK_BIN}/ss"
#!/bin/sh
if [ -n "${MOCK_PORT_BUSY:-}" ]; then
    printf 'UNCONN 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$MOCK_PORT_BUSY"
fi
exit 0
EOF
chmod +x "${MOCK_BIN}/ss"

cat << 'EOF' > "${MOCK_BIN}/netstat"
#!/bin/sh
if [ -n "${MOCK_PORT_BUSY:-}" ]; then
    printf 'udp 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$MOCK_PORT_BUSY"
fi
exit 0
EOF
chmod +x "${MOCK_BIN}/netstat"

cat << 'EOF' > "${MOCK_BIN}/pidof"
#!/bin/sh
if [ "${1:-}" = "wg_server" ] && [ -n "${MOCK_WG_SERVER_PID:-}" ]; then
    echo "$MOCK_WG_SERVER_PID"
    exit 0
fi
exit 1
EOF
chmod +x "${MOCK_BIN}/pidof"

cat << 'EOF' > "${MOCK_BIN}/ping"
#!/bin/sh
exit 1
EOF
chmod +x "${MOCK_BIN}/ping"

# Mock boringtun-cli-armv7 binary
cat << 'EOF' > "$TEST_STAGED_SRC"
#!/bin/sh
iface=""
for arg in "$@"; do iface="$arg"; done
if [ "${MOCK_NO_TUN:-0}" != "1" ] && [ -n "$iface" ]; then
    mkdir -p "${MOCK_NET}/ifaces/${iface}"
    echo "${iface}: <DOWN>" > "${MOCK_NET}/ifaces/${iface}/link"
fi
if [ "${MOCK_EARLY_EXIT:-0}" = "1" ]; then
    exit 1
fi
sleep 60 &
_sp=$!
trap 'kill "$_sp" 2>/dev/null || true; exit 0' TERM INT HUP
wait "$_sp" 2>/dev/null || true
EOF
chmod +x "$TEST_STAGED_SRC"

# Setup active production wg0 in mock network
mkdir -p "$MOCK_NET/ifaces/wg0"
echo "wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420" > "$MOCK_NET/ifaces/wg0/link"
echo "    inet 10.99.0.1/24 scope global wg0" > "$MOCK_NET/ifaces/wg0/addr"
echo "10.99.0.0/24 dev wg0 table main" >> "$MOCK_NET/routes/table_main"
echo "32764:  from 10.99.0.0/24 lookup main" >> "$MOCK_NET/rules/list"

export PATH="${MOCK_BIN}:$PATH"
export MOCK_NET
export WG_DIR="$TEST_WG_DIR"
export WG_TMP_DIR="$TEST_TMP_DIR"
export WG_SOCK_DIR="$TEST_SOCK_DIR"
export WG_PID_FILE="$TEST_PID_FILE"
export WG_LOG_FILE="$TEST_LOG_FILE"
export WG_MANIFEST="$TEST_MANIFEST"
export STAGED_SRC="$TEST_STAGED_SRC"
export BORINGTUN_BIN="${TEST_WG_DIR}/boringtun-cli-armv7"
export PROC_ROOT="/proc"

assert_eq() {
    _desc="$1"
    _exp="$2"
    _act="$3"
    if [ "$_exp" = "$_act" ]; then
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $_desc (Expected: '$_exp' | Got: '$_act')"
        FAILED=$((FAILED + 1))
        exit 1
    fi
}

echo "================================================================================"
echo ">>> RUNNING P0-4 BORINGTUN WG1 ISOLATION & MANIFEST TEST HARNESS"
echo ">>> Temp Root: $TMP_ROOT"
echo "================================================================================"

# ------------------------------------------------------------------------------
# TEST 1: Production wg0 / port 51820 / subnet 10.99.0.0/24 Boundary Guard
# ------------------------------------------------------------------------------
echo "--- TEST 1: Production wg0 Guard (exit 99) ---"
_rc=0; WG_IFACE=wg0 sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1 || _rc=$?
assert_eq "Deploy refuses WG_IFACE=wg0 with exit 99" "99" "$_rc"

_rc=0; WG_IFACE=wg0 sh "$TEARDOWN_SCRIPT" >/dev/null 2>&1 || _rc=$?
assert_eq "Teardown refuses WG_IFACE=wg0 with exit 99" "99" "$_rc"

_rc=0; WG_PORT=51820 sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1 || _rc=$?
assert_eq "Deploy refuses reserved port 51820 with exit 99" "99" "$_rc"

_rc=0; WG_SUBNET="10.99.0.0/24" sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1 || _rc=$?
assert_eq "Deploy refuses wg0 subnet with exit 99" "99" "$_rc"

# ------------------------------------------------------------------------------
# TEST 2: --dry-run Strictly Non-Mutating
# ------------------------------------------------------------------------------
echo "--- TEST 2: --dry-run Performs Zero Filesystem or Network Mutations ---"
if sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [PASS] deploy_wg1.sh --dry-run succeeded"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] deploy_wg1.sh --dry-run exited non-zero"
    FAILED=$((FAILED + 1)); exit 1
fi
assert_eq "Dry-run did NOT create WG_DIR" "0" "$([ ! -d "$TEST_WG_DIR" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT copy boringtun binary" "0" "$([ ! -e "$BORINGTUN_BIN" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT create SOCK_DIR" "0" "$([ ! -d "$TEST_SOCK_DIR" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT create TMP_DIR" "0" "$([ ! -d "$TEST_TMP_DIR" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT create PID file" "0" "$([ ! -e "$TEST_PID_FILE" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT create manifest" "0" "$([ ! -e "$TEST_MANIFEST" ] && echo 0 || echo 1)"
assert_eq "Dry-run did NOT create wg1 iface" "0" "$([ ! -d "$MOCK_NET/ifaces/wg1" ] && echo 0 || echo 1)"

# ------------------------------------------------------------------------------
# TEST 3: Preflight Collision Rejection
# ------------------------------------------------------------------------------
echo "--- TEST 3: Preflight Collision Rejection (iface/port/ip/table/rule/pid) ---"
# 3A: Existing wg1 iface
mkdir -p "$MOCK_NET/ifaces/wg1"
if sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [FAIL] Allowed existing wg1 interface"; exit 1
else
    echo "  [PASS] Rejected existing wg1 interface"; PASSED=$((PASSED + 1))
fi
rm -rf "$MOCK_NET/ifaces/wg1"

# 3B: UDP port 51821 busy
if MOCK_PORT_BUSY=51821 sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [FAIL] Allowed busy UDP port 51821"; exit 1
else
    echo "  [PASS] Rejected busy UDP port 51821"; PASSED=$((PASSED + 1))
fi

# 3C: Existing route in table 101
echo "172.30.0.0/24 dev eth0 table 101" > "$MOCK_NET/routes/table_101"
if sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [FAIL] Allowed non-empty table 101 collision"; exit 1
else
    echo "  [PASS] Rejected shared non-empty routing table 101"; PASSED=$((PASSED + 1))
fi
: > "$MOCK_NET/routes/table_101"

# 3D: Existing policy rule
echo "32760:  from 10.99.1.0/24 lookup 101" >> "$MOCK_NET/rules/list"
if sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [FAIL] Allowed duplicate policy rule"; exit 1
else
    echo "  [PASS] Rejected duplicate policy rule"; PASSED=$((PASSED + 1))
fi
grep -vF "from 10.99.1.0/24" "$MOCK_NET/rules/list" > "$MOCK_NET/rules/list.tmp"
mv "$MOCK_NET/rules/list.tmp" "$MOCK_NET/rules/list"

# 3E: Stale PID file
echo "99999" > "$TEST_PID_FILE"
if sh "$DEPLOY_SCRIPT" --dry-run >/dev/null 2>&1; then
    echo "  [FAIL] Allowed deploy with existing PID file"; exit 1
else
    echo "  [PASS] Rejected deploy with existing PID file"; PASSED=$((PASSED + 1))
fi
rm -f "$TEST_PID_FILE"

# ------------------------------------------------------------------------------
# TEST 4: Atomic Deploy + Manifest + Pre-Existing Shared Dir Preservation
# ------------------------------------------------------------------------------
echo "--- TEST 4: Happy-Path Deploy + Manifest + Shared WG_DIR Preservation ---"
mkdir -p "$TEST_WG_DIR"
printf 'existing_tool\n' > "${TEST_WG_DIR}/keep_tool"

WG0_PRE=$(cat "$MOCK_NET/ifaces/wg0/link" "$MOCK_NET/ifaces/wg0/addr" "$MOCK_NET/routes/table_main" "$MOCK_NET/rules/list")
if sh "$DEPLOY_SCRIPT" >/dev/null 2>&1; then
    echo "  [PASS] deploy_wg1.sh completed with exit 0"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] deploy_wg1.sh failed on happy path"; FAILED=$((FAILED + 1)); exit 1
fi

assert_eq "Manifest exists" "1" "$([ -f "$TEST_MANIFEST" ] && echo 1 || echo 0)"
assert_eq "Manifest status is ACTIVE" "ACTIVE" "$(grep '^DEPLOY_STATUS=' "$TEST_MANIFEST" | sed 's/^DEPLOY_STATUS=//')"
assert_eq "Manifest tracks OWNED_WG_DIR_CREATED=0 (pre-existing dir)" "0" "$(grep '^OWNED_WG_DIR_CREATED=' "$TEST_MANIFEST" | sed 's/^OWNED_WG_DIR_CREATED=//')"
assert_eq "Manifest tracks OWNED_BIN_CREATED=1" "1" "$(grep '^OWNED_BIN_CREATED=' "$TEST_MANIFEST" | sed 's/^OWNED_BIN_CREATED=//')"
assert_eq "wg1 interface configured" "1" "$([ -d "$MOCK_NET/ifaces/wg1" ] && echo 1 || echo 0)"
assert_eq "wg1 route added in table 101" "1" "$(grep -c '10.99.1.0/24 dev wg1' "$MOCK_NET/routes/table_101")"
assert_eq "wg1 policy rule added" "1" "$(grep -c 'from 10.99.1.0/24 lookup 101' "$MOCK_NET/rules/list")"

# ------------------------------------------------------------------------------
# TEST 5: Owned-Only Teardown (Zero pkill -f / Zero table flush / wg0 Invariance)
# ------------------------------------------------------------------------------
echo "--- TEST 5: Owned-Only Teardown Leaves Unrelated Process, Route, File & wg0 Untouched ---"
# Inject 1) unrelated route into table 101, 2) unrelated decoy process matching old pkill pattern
echo "172.30.0.0/24 dev eth0 table 101" >> "$MOCK_NET/routes/table_101"
sh -c 'sleep 30 # boringtun-cli-armv7 wg1 decoy' >/dev/null 2>&1 &
DECOY_PID=$!
BG_PIDS="$BG_PIDS $DECOY_PID"
DEPLOYED_PID=$(cat "$TEST_PID_FILE")

if sh "$TEARDOWN_SCRIPT" >/dev/null 2>&1; then
    echo "  [PASS] teardown_wg1.sh completed with exit 0"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] teardown_wg1.sh failed"; FAILED=$((FAILED + 1)); exit 1
fi

assert_eq "Owned boringtun PID terminated" "0" "$(kill -0 "$DEPLOYED_PID" 2>/dev/null && echo 1 || echo 0)"
assert_eq "Unrelated decoy process survived (no pkill -f)" "1" "$(kill -0 "$DECOY_PID" 2>/dev/null && echo 1 || echo 0)"
assert_eq "wg1 interface removed" "0" "$([ -d "$MOCK_NET/ifaces/wg1" ] && echo 1 || echo 0)"
assert_eq "Owned wg1 route deleted" "0" "$(grep -c '10.99.1.0/24 dev wg1' "$MOCK_NET/routes/table_101" || true)"
assert_eq "Unrelated route in table 101 preserved (no blanket flush)" "1" "$(grep -c '172.30.0.0/24 dev eth0' "$MOCK_NET/routes/table_101" || true)"
assert_eq "Owned wg1 policy rule deleted" "0" "$(grep -c 'from 10.99.1.0/24 lookup 101' "$MOCK_NET/rules/list" || true)"
assert_eq "Pre-existing file in WG_DIR preserved" "1" "$([ -f "${TEST_WG_DIR}/keep_tool" ] && echo 1 || echo 0)"
assert_eq "Owned boringtun binary removed" "0" "$([ -e "$BORINGTUN_BIN" ] && echo 1 || echo 0)"
assert_eq "Manifest removed after clean teardown" "0" "$([ -e "$TEST_MANIFEST" ] && echo 1 || echo 0)"

WG0_POST=$(cat "$MOCK_NET/ifaces/wg0/link" "$MOCK_NET/ifaces/wg0/addr" "$MOCK_NET/routes/table_main" "$MOCK_NET/rules/list")
assert_eq "Production wg0 pre vs post byte-for-byte invariant" "$WG0_PRE" "$WG0_POST"

kill -9 "$DECOY_PID" 2>/dev/null || true
wait "$DECOY_PID" 2>/dev/null || true
: > "$MOCK_NET/routes/table_101"

# ------------------------------------------------------------------------------
# TEST 6: Mid-Deploy Failure Triggers Atomic Rollback of Partial Resources
# ------------------------------------------------------------------------------
echo "--- TEST 6: Partial Deploy Failure Atomic Cleanup ---"
rm -rf "$TEST_WG_DIR"
if MOCK_FAIL_IP_RULE_ADD=1 sh "$DEPLOY_SCRIPT" >/dev/null 2>&1; then
    echo "  [FAIL] Deploy succeeded despite ip rule add failure"; exit 1
else
    echo "  [PASS] Deploy rejected ip rule add error (no || true swallowing)"
    PASSED=$((PASSED + 1))
fi
assert_eq "Rollback removed wg1 interface after rule failure" "0" "$([ -d "$MOCK_NET/ifaces/wg1" ] && echo 1 || echo 0)"
assert_eq "Rollback removed table 101 route after rule failure" "0" "$(grep -c '10.99.1.0/24' "$MOCK_NET/routes/table_101" || true)"
assert_eq "Rollback removed PID file after rule failure" "0" "$([ -e "$TEST_PID_FILE" ] && echo 1 || echo 0)"
assert_eq "Rollback removed copied binary after rule failure" "0" "$([ -e "$BORINGTUN_BIN" ] && echo 1 || echo 0)"
assert_eq "Rollback removed newly created WG_DIR" "0" "$([ -d "$TEST_WG_DIR" ] && echo 1 || echo 0)"
assert_eq "Rollback removed manifest after partial failure" "0" "$([ -e "$TEST_MANIFEST" ] && echo 1 || echo 0)"

# ------------------------------------------------------------------------------
# TEST 7: Teardown Refusals (Missing Manifest & Recycled PID Protection)
# ------------------------------------------------------------------------------
echo "--- TEST 7: Teardown Missing Manifest Refusal & Recycled PID Guard ---"
echo "172.30.0.0/24 dev eth0 table 101" > "$MOCK_NET/routes/table_101"
if sh "$TEARDOWN_SCRIPT" >/dev/null 2>&1; then
    echo "  [FAIL] Teardown succeeded without manifest"; exit 1
else
    echo "  [PASS] Teardown cleanly refused missing manifest"; PASSED=$((PASSED + 1))
fi
assert_eq "Refused teardown left table 101 untouched" "1" "$(grep -c '172.30.0.0/24' "$MOCK_NET/routes/table_101" || true)"
: > "$MOCK_NET/routes/table_101"

# Recycled PID mock: live sleep process whose mock /proc/$PID/cmdline is unrelated "httpd"
sleep 30 &
RECYCLED_PID=$!
BG_PIDS="$BG_PIDS $RECYCLED_PID"
FAKE_PROC="${TMP_ROOT}/fake_proc"
mkdir -p "${FAKE_PROC}/${RECYCLED_PID}"
printf 'uhttpd\0-f\0' > "${FAKE_PROC}/${RECYCLED_PID}/cmdline"
cat << EOF > "$TEST_MANIFEST"
DEPLOY_STATUS=ACTIVE
OWNED_IFACE=wg1
OWNED_PORT=51821
OWNED_SUBNET=10.99.1.0/24
OWNED_SERVER_IP=10.99.1.1/24
OWNED_TABLE=101
OWNED_PID=${RECYCLED_PID}
OWNED_PID_FILE=${TEST_PID_FILE}
OWNED_LOG_FILE=${TEST_LOG_FILE}
OWNED_WG_DIR=${TEST_WG_DIR}
OWNED_WG_DIR_CREATED=0
OWNED_BIN_PATH=${BORINGTUN_BIN}
OWNED_BIN_CREATED=0
OWNED_SOCK_DIR=${TEST_SOCK_DIR}
OWNED_SOCK_DIR_CREATED=0
OWNED_SOCK_PRIMARY=${TEST_SOCK_DIR}/wg1.sock
OWNED_SOCK_TMP=${TEST_TMP_DIR}/wg1.sock
OWNED_TMP_DIR=${TEST_TMP_DIR}
OWNED_TMP_DIR_CREATED=0
OWNED_ROUTE_CREATED=0
OWNED_RULE_CREATED=0
EOF

PROC_ROOT="$FAKE_PROC" sh "$TEARDOWN_SCRIPT" >/dev/null 2>&1 || true
assert_eq "Recycled unrelated PID was NOT killed during teardown" "1" "$(kill -0 "$RECYCLED_PID" 2>/dev/null && echo 1 || echo 0)"
kill -9 "$RECYCLED_PID" 2>/dev/null || true
wait "$RECYCLED_PID" 2>/dev/null || true

# ------------------------------------------------------------------------------
# TEST 8: benchmark_wg0_vs_wg1.sh Non-Fabrication When /proc Unavailable
# ------------------------------------------------------------------------------
echo "--- TEST 8: benchmark_wg0_vs_wg1.sh Unavailable Telemetry Guard ---"
BENCH_JSON="${TMP_ROOT}/bench_out.json"
OUTPUT_JSON="$BENCH_JSON" PROC_ROOT="${TMP_ROOT}/empty_proc" WG1_PID_FILE="${TMP_ROOT}/no_wg1.pid" \
    sh "$BENCH_SCRIPT" >/dev/null 2>&1
assert_eq "Benchmark JSON created" "1" "$([ -f "$BENCH_JSON" ] && echo 1 || echo 0)"
if grep -q '"pid": "UNAVAILABLE"' "$BENCH_JSON" && ! grep -q '20384' "$BENCH_JSON"; then
    echo "  [PASS] Benchmark reported UNAVAILABLE instead of fabricated baseline 1420/20384"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Benchmark fabricated fallback baseline in JSON"
    cat "$BENCH_JSON"
    FAILED=$((FAILED + 1)); exit 1
fi

echo "================================================================================"
echo "P0-4 WG1 ISOLATION TEST COMPLETE: ${PASSED} assertions passed, ${FAILED} assertions failed."
echo "================================================================================"
[ "$FAILED" -eq 0 ]
