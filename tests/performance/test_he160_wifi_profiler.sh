#!/bin/sh
# tests/performance/test_he160_wifi_profiler.sh
# Hermetic test suite for performance/benchmarks/he160_wifi_profiler.sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILER="${REPO_ROOT}/performance/benchmarks/he160_wifi_profiler.sh"
TEST_DIR="$(mktemp -d /tmp/test_he160_prof.XXXXXX)"
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

echo "=== Test 1: --dry-run reports read-only probes without network calls ==="
_dry_out=$(sh "$PROFILER" --dry-run --target 192.168.31.1 --ssh-port 56789 --duration 2)
assert_contains "Dry-run prints read-only banner" "$_dry_out" "QCN6102 HE160 Read-Only Profiler"
assert_contains "Dry-run prints pinned host key path" "$_dry_out" "cr8818_host_key.pub"
assert_contains "Dry-run notes skipped iperf3 target" "$_dry_out" "SKIPPED_NO_TARGET"

echo "=== Test 2: Valid QCN6102 wl0 mock telemetry, PCIe IRQ delta & UNSUPPORTED_IOCTL ==="
MOCK1="${TEST_DIR}/mock1"
mkdir -p "${MOCK1}/bin"

cat << 'EOF' > "${MOCK1}/bin/ssh"
#!/bin/sh
cat << 'MOCKTELEM'
@@IW_WL0@@
Interface wl0
	ifindex 12
	wdev 0x1
	type AP
	channel 36 (5180 MHz), width: 160 MHz, center1: 5250 MHz
	txpower 23.00 dBm
@@IW_WL0_STA@@
Station 02:00:00:00:00:01 (on wl0)
	rx bitrate:	2401.9 MBit/s 160MHz HE-MCS 11 HE-NSS 2 HE-GI 0
Station 02:00:00:00:00:02 (on wl0)
	rx bitrate:	1200.0 MBit/s 80MHz HE-MCS 9 HE-NSS 2 HE-GI 0
@@IWPRIV_WL0@@
get_chwidth=>wl0       get_chwidth:3  
get_ampdu=>wl0       get_ampdu:64  
get_amsdu=>wl0       get_amsdu:3  
get_preCACEn=>Invalid command : get_preCACEn
get_he_ul_ofdma=>wl0       get_he_ul_ofdma:1  
get_txbf=>wl0       get_txbf:3  
@@DMESG_DFS@@
[   42.100000] ieee80211: current channel is not pre cac, skip cac? 0
@@QDISC@@
qdisc fq_codel 8001: dev br-lan root refcnt 2 limit 1024p flows 1024 quantum 1514 target 5.0ms interval 100.0ms
@@IRQ_T0@@
           CPU0       CPU1
 55:       1000        200     GICv3  pci0_wlan_ce_1
 56:        500        100     GICv3  pci0_wlan_ce_2
 57:       2000        400     GICv3  pci0_wlan_grp_dp_3
 58:       1500        300     GICv3  rxdma2host-destination-ring-mac1
@@IRQ_T1@@
           CPU0       CPU1
 55:       1300        300     GICv3  pci0_wlan_ce_1
 56:        600        200     GICv3  pci0_wlan_ce_2
 57:       2600        700     GICv3  pci0_wlan_grp_dp_3
 58:       2000        600     GICv3  rxdma2host-destination-ring-mac1
@@END@@
MOCKTELEM
EOF
chmod +x "${MOCK1}/bin/ssh"

cat << 'EOF' > "${MOCK1}/bin/ping"
#!/bin/sh
echo "PING 192.168.31.1 (192.168.31.1) 56(84) bytes of data."
echo "10 packets transmitted, 10 received, 0% packet loss, time 100ms"
echo "rtt min/avg/max/mdev = 1.10/1.50/2.00/0.20 ms"
EOF
chmod +x "${MOCK1}/bin/ping"

_tmp_before=$(find /tmp -maxdepth 1 -name 'he160_prof.*' 2>/dev/null | wc -l)
_json1=$(sh "$PROFILER" --target 192.168.31.1 --duration 1 --mock-dir "$MOCK1" --json)
_tmp_after=$(find /tmp -maxdepth 1 -name 'he160_prof.*' 2>/dev/null | wc -l)

assert_eq "No leaked /tmp/he160_prof dirs" "$_tmp_before" "$_tmp_after"
assert_contains "Channel 36 parsed" "$_json1" '"channel": "36 (5180 MHz)"'
assert_contains "HE160 width parsed" "$_json1" '"width": "160 MHz"'
assert_contains "Center frequency 5250 parsed" "$_json1" '"center1": "5250 MHz"'
assert_contains "TX power parsed" "$_json1" '"txpower": "23.00 dBm"'
assert_contains "Station count = 2" "$_json1" '"associated_stations": 2'
assert_contains "get_chwidth = 3" "$_json1" '"iwpriv_chwidth": "3"'
assert_contains "UNSUPPORTED_IOCTL flagged for get_preCACEn" "$_json1" '"iwpriv_precac_en": "UNSUPPORTED_IOCTL"'
assert_contains "DFS pre-CAC dmesg parsed" "$_json1" '"dfs_dmesg_status": "NOT_PRE_CAC_CAC_REQUIRED"'
assert_contains "br-lan qdisc parsed" "$_json1" '"qdisc_br_lan": "fq_codel"'
# Deltas: CPU0=(300+100+600+500)=1500, CPU1=(100+100+300+300)=800 -> total=2300, cpu0_pct=65, cpu1_pct=35
assert_contains "Wi-Fi DMA IRQ CPU0 delta = 1500" "$_json1" '"cpu0": 1500'
assert_contains "Wi-Fi DMA IRQ CPU1 delta = 800" "$_json1" '"cpu1": 800'
assert_contains "Wi-Fi DMA IRQ CPU0 pct = 65" "$_json1" '"cpu0_pct": 65'
assert_contains "Wi-Fi DMA IRQ CPU1 pct = 35" "$_json1" '"cpu1_pct": 35'
assert_contains "Skipped throughput when no iperf target" "$_json1" '"load_status": "SKIPPED_NO_TARGET"'
assert_contains "Unloaded RTT = 1.50 ms" "$_json1" '"unloaded_rtt_avg_ms": 1.50'

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$_json1" | python3 -c "import sys,json; json.load(sys.stdin)"
    echo "  [PASS] JSON payload parses cleanly in Python"
    PASSED=$((PASSED + 1))
fi

echo "=== Test 3: Loaded vs Unloaded Bufferbloat Delta w/ Mock iperf3 ==="
MOCK2="${TEST_DIR}/mock2"
cp -R "$MOCK1" "$MOCK2"

cat << EOF > "${MOCK2}/bin/ping"
#!/bin/sh
if [ -f "${MOCK2}/load_active" ]; then
    echo "10 packets transmitted, 10 received, 0% packet loss, time 200ms"
    echo "rtt min/avg/max/mdev = 3.10/4.75/6.00/0.40 ms"
else
    touch "${MOCK2}/load_active"
    echo "10 packets transmitted, 10 received, 0% packet loss, time 100ms"
    echo "rtt min/avg/max/mdev = 1.10/1.50/2.00/0.20 ms"
fi
EOF
chmod +x "${MOCK2}/bin/ping"

cat << 'EOF' > "${MOCK2}/bin/iperf3"
#!/bin/sh
cat << 'IPFJSON'
{
  "end": {
    "sum_received": {
      "bits_per_second": 912500000.0
    }
  }
}
IPFJSON
EOF
chmod +x "${MOCK2}/bin/iperf3"

_json2=$(sh "$PROFILER" --target 192.168.31.1 --duration 1 --iperf-target 192.168.31.10 --mock-dir "$MOCK2" --json)
assert_contains "Loaded measurement status MEASURED" "$_json2" '"load_status": "MEASURED"'
assert_contains "Loaded RTT = 4.75" "$_json2" '"loaded_rtt_avg_ms": 4.75'
assert_contains "Bufferbloat delta = 3.25 ms" "$_json2" '"bufferbloat_delta_ms": 3.25'
assert_contains "Throughput = 912.50 Mbps" "$_json2" '"throughput_mbps": 912.50'

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$_json2" | python3 -c "import sys,json; json.load(sys.stdin)"
    echo "  [PASS] Loaded JSON payload parses cleanly in Python"
    PASSED=$((PASSED + 1))
fi

echo "=== Test 4: SSH failure fails closed with non-zero exit ==="
MOCK3="${TEST_DIR}/mock3"
mkdir -p "${MOCK3}/bin"
cat << 'EOF' > "${MOCK3}/bin/ssh"
#!/bin/sh
exit 255
EOF
chmod +x "${MOCK3}/bin/ssh"

_rc=0
_err_out=$(sh "$PROFILER" --target 192.168.31.1 --mock-dir "$MOCK3" 2>&1) || _rc=$?
assert_eq "Unreachable router SSH exits 1" "1" "$_rc"
assert_contains "Error message reports telemetry collection failure" "$_err_out" "Unable to collect read-only router telemetry"

echo "HE160 PROFILER TEST COMPLETE: ${PASSED} passed, ${FAILED} failed."
