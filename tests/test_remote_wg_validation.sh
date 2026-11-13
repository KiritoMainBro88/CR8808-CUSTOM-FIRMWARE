#!/bin/sh
# tests/test_remote_wg_validation.sh
# Hermetic test suite for scripts/validate_remote_wg_path.sh
# Tests offline .conf validation, secret non-disclosure, and 7-stage path verification.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/validate_remote_wg_path.sh"
TEST_DIR="$(mktemp -d /tmp/test_wg_val.XXXXXX)"
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PASSED=0
FAILED=0

assert_eq() {
    _desc="$1"
    _exp="$2"
    _act="$3"
    if [ "$_exp" = "$_act" ]; then
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $_desc (Expected '$_exp', got '$_act')"
        FAILED=$((FAILED + 1))
        exit 1
    fi
}

assert_contains() {
    _desc="$1"
    _hay="$2"
    _needle="$3"
    if printf '%s' "$_hay" | grep -q "$_needle"; then
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $_desc (Missing '$_needle')"
        FAILED=$((FAILED + 1))
        exit 1
    fi
}

assert_not_contains() {
    _desc="$1"
    _hay="$2"
    _needle="$3"
    if printf '%s' "$_hay" | grep -q "$_needle"; then
        echo "  [FAIL] $_desc (Secret/forbidden string leaked: '$_needle')"
        FAILED=$((FAILED + 1))
        exit 1
    else
        echo "  [PASS] $_desc"
        PASSED=$((PASSED + 1))
    fi
}

FAKE_PRIV="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAc="
FAKE_PUB="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBc="

echo "=== Test 1: Valid hardened split config passes with zero secret leakage ==="
cat << EOF > "${TEST_DIR}/good_split.conf"
[Interface]
PrivateKey = ${FAKE_PRIV}
Address = 10.99.0.2/24
MTU = 1280

[Peer]
PublicKey = ${FAKE_PUB}
Endpoint = example.duckdns.org:51820
AllowedIPs = 10.99.0.0/24, 192.168.31.0/24
PersistentKeepalive = 25
EOF

_out=$(sh "$VALIDATOR" --validate-conf "${TEST_DIR}/good_split.conf" --json)
assert_contains "Valid split conf status PASS" "$_out" '"status": "PASS"'
assert_contains "Zero warnings on good split conf" "$_out" '"warnings": 0'
assert_not_contains "PrivateKey never printed" "$_out" "$FAKE_PRIV"

echo "=== Test 2: Full config with ::/0 without IPv6 Address fails cleanly ==="
cat << EOF > "${TEST_DIR}/bad_v6.conf"
[Interface]
PrivateKey = ${FAKE_PRIV}
Address = 10.99.0.2/24
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = ${FAKE_PUB}
Endpoint = example.duckdns.org:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

_rc=0
_bad_out=$(sh "$VALIDATOR" --validate-conf "${TEST_DIR}/bad_v6.conf" --json 2>&1) || _rc=$?
assert_eq "Broken ::/0 conf exits non-zero" "1" "$_rc"
assert_contains "Reports IPv6 blackhole defect" "$_bad_out" 'IPv6_default_route_without_v6_address'
assert_contains "Reports external DNS warning" "$_bad_out" 'External_DNS_blocked_risk'
assert_contains "Reports MTU warning" "$_bad_out" 'MTU_above_1380_pppoe_nat_risk'
assert_not_contains "PrivateKey never leaked on failure" "$_bad_out" "$FAKE_PRIV"

echo "=== Test 3: Dry-run 7-stage path check ==="
_dry_out=$(sh "$VALIDATOR" --verify-path --dry-run)
assert_contains "Dry-run describes 7 stages" "$_dry_out" 'Stage 7:'

echo "=== Test 4: Mock 7-stage remote path verification (Happy Path) ==="
MOCK="${TEST_DIR}/mock_happy"
mkdir -p "${MOCK}/bin"
NOW_EPOCH=$(date +%s)
echo "0" > "${MOCK}/tx_count"
printf 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCmocktestkey root@cr8818\n' > "${MOCK}/host_key.pub"

cat << EOF > "${MOCK}/bin/wg"
#!/bin/sh
case "\$3" in
  latest-handshakes)
    echo "peerkey123 $((NOW_EPOCH - 5))"
    ;;
  transfer)
    c=\$(cat "${MOCK}/tx_count")
    c=\$((c + 1024))
    echo "\$c" > "${MOCK}/tx_count"
    echo "peerkey123 \$c \$((c * 2))"
    ;;
esac
EOF
cat << 'EOF' > "${MOCK}/bin/ping"
#!/bin/sh
exit 0
EOF
cat << 'EOF' > "${MOCK}/bin/ip"
#!/bin/sh
echo "192.168.31.1 via 10.99.0.1 dev wg0 src 10.99.0.2"
EOF
cat << 'EOF' > "${MOCK}/bin/ssh"
#!/bin/sh
echo "Linux xiaomi 4.4.60 armv7l GNU/Linux"
exit 0
EOF
chmod +x "${MOCK}/bin/"*

_happy_out=$(sh "$VALIDATOR" --verify-path --mock-dir "$MOCK" --host-key "${MOCK}/host_key.pub" --sample-seconds 0 --json)
assert_contains "7-stage mock happy path PASS" "$_happy_out" '"status": "PASS"'
assert_contains "Pinned SSH stage PASS" "$_happy_out" '"pinned_ssh": "PASS"'

echo "=== Test 5: Stale handshake fails fast at Stage 1 ==="
cat << EOF > "${MOCK}/bin/wg"
#!/bin/sh
echo "peerkey123 $((NOW_EPOCH - 900))"
EOF
chmod +x "${MOCK}/bin/wg"
_rc=0
_stale_out=$(sh "$VALIDATOR" --verify-path --mock-dir "$MOCK" --host-key "${MOCK}/host_key.pub" --sample-seconds 0 --json) || _rc=$?
assert_eq "Stale handshake exits non-zero" "1" "$_rc"
assert_contains "Handshake stage reports FAIL" "$_stale_out" '"handshake": "FAIL"'

echo "=== Test 6: Route hijack (NordLynx/campus route) caught at Stage 4 ==="
cat << EOF > "${MOCK}/bin/wg"
#!/bin/sh
case "\$3" in
  latest-handshakes) echo "peerkey123 $((NOW_EPOCH - 2))" ;;
  transfer) echo "peerkey123 4096 8192" ;;
esac
EOF
cat << 'EOF' > "${MOCK}/bin/ip"
#!/bin/sh
echo "192.168.31.1 via 10.5.0.1 dev NordLynx src 10.5.0.2"
EOF
chmod +x "${MOCK}/bin/wg" "${MOCK}/bin/ip"
_rc=0
_rt_out=$(sh "$VALIDATOR" --verify-path --mock-dir "$MOCK" --host-key "${MOCK}/host_key.pub" --sample-seconds 0 --json) || _rc=$?
assert_eq "Route mismatch exits non-zero" "1" "$_rc"
assert_contains "Reports route_mismatch" "$_rt_out" 'route_mismatch'

echo "=== ALL ${PASSED} REMOTE WG VALIDATION TESTS PASSED (FAILED=${FAILED}) ==="
