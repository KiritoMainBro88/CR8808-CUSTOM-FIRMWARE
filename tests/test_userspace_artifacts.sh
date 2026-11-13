#!/bin/sh
# tests/test_userspace_artifacts.sh
# Hermetic + Real-Artifact Verification Tests for scripts/verify_userspace_artifacts.sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFIER="${REPO_ROOT}/scripts/verify_userspace_artifacts.sh"
TEST_DIR="$(mktemp -d /tmp/test_usr_verify.XXXXXX)"
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

echo "=== Test 1: Real ARMv7 artifacts pass SHA-256, ELF32 ARM & footprint checks ==="
STAGE_OUT="${TEST_DIR}/staged"
_json=$(sh "$VERIFIER" --stage-dir "$STAGE_OUT" --json)

assert_contains "Total 3 artifacts checked" "$_json" '"total": 3'
assert_contains "Passed 3 artifacts" "$_json" '"passed": 3'
assert_contains "Failed 0 artifacts" "$_json" '"failed": 0'
assert_contains "tmpfs budget PASS" "$_json" '"tmpfs_footprint_status": "PASS"'
assert_contains "iperf3-armv7 verified" "$_json" '"binary":"iperf3-armv7"'
assert_contains "ethtool-armv7 verified" "$_json" '"binary":"ethtool-armv7"'
assert_contains "boringtun-cli-armv7 verified" "$_json" '"binary":"boringtun-cli-armv7"'
assert_contains "All SHA256 hashes PASS" "$_json" '"sha256":"PASS"'

for _b in iperf3-armv7 ethtool-armv7 boringtun-cli-armv7; do
    if [ -x "${STAGE_OUT}/${_b}" ]; then
        echo "  [PASS] Staged executable present: $_b"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] Missing staged executable: $_b"
        FAILED=$((FAILED + 1))
        exit 1
    fi
done

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['passed'] == 3 and d['failed'] == 0
for a in d['artifacts']:
    assert a['sha256'] == 'PASS'
    assert a['elf'].startswith('PASS_ARM32')
"
    echo "  [PASS] JSON schema & all ARM32 ELF checks validated in Python"
    PASSED=$((PASSED + 1))
fi

echo "=== Test 2: Tampered SHA256SUMS / corrupted binary fails closed (exit 1) ==="
BAD_ROOT="${TEST_DIR}/bad_artifacts"
mkdir -p "${BAD_ROOT}/m12_userspace" "${BAD_ROOT}/m12_wireguard"
cp -R "${REPO_ROOT}/artifacts/m12_userspace/." "${BAD_ROOT}/m12_userspace/"
cp -R "${REPO_ROOT}/artifacts/m12_wireguard/." "${BAD_ROOT}/m12_wireguard/"
# Corrupt iperf3-armv7 copy without updating SHA256SUMS
printf 'CORRUPT' >> "${BAD_ROOT}/m12_userspace/iperf3-armv7"

_rc=0
_bad_json=$(sh "$VERIFIER" --artifacts-root "$BAD_ROOT" --json 2>&1) || _rc=$?
assert_eq "Corrupted artifact causes non-zero exit" "1" "$_rc"
assert_contains "Failed count = 1 on single corrupted binary" "$_bad_json" '"failed": 1'
assert_contains "Tampered binary flagged FAIL" "$_bad_json" '"binary":"iperf3-armv7".*"sha256":"FAIL"'

echo "=== Test 3: Exceeding RAM_LIMIT_KB emits WARN_EXCEEDS_TMPFS_BUDGET ==="
_warn_json=$(RAM_LIMIT_KB=100 sh "$VERIFIER" --json)
assert_contains "Tight RAM budget triggers warning flag" "$_warn_json" '"tmpfs_footprint_status": "WARN_EXCEEDS_TMPFS_BUDGET"'

echo "USERSPACE ARTIFACT VERIFICATION TEST COMPLETE: ${PASSED} passed, ${FAILED} failed."
