#!/bin/bash
# scripts/m11_1_r0_baseline_audit.sh
# Milestone M11.1.0.1: Hardened, In-Memory Stream Class R0 Read-Only Live Baseline Audit
# Pure In-Memory Stream Processing: ZERO temporary files created on router (/tmp untouched)
# Target: 192.168.31.1:56789
# Usage: export SSHPASS="<password>"; ./scripts/m11_1_r0_baseline_audit.sh

set -uo pipefail

ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE:-/tmp/cr8818_known_hosts}"
OUTPUT_FILE="${OUTPUT_FILE:-/mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/reports/M11_1_R0_LIVE_BASELINE_RAW.txt}"

if [ -z "${SSHPASS:-}" ]; then
    echo "ERROR: SSHPASS environment variable is required to avoid command-line argument leakage."
    echo "Usage: export SSHPASS='mysecret'; $0"
    exit 1
fi

PINNED_KEY_FILE="${PINNED_KEY_FILE:-config/cr8818_host_key.pub}"
EXPECTED_FINGERPRINT="SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM"
SANITIZER="scripts/sanitize_telemetry.sh"

if [ ! -f "$PINNED_KEY_FILE" ]; then
    echo "ERROR: Pinned host key file $PINNED_KEY_FILE not found." >&2
    exit 1
fi

echo "Verifying pinned host key fingerprint for ${ROUTER_IP}:${ROUTER_PORT}..."
ACTUAL_FINGERPRINT=$(ssh-keygen -l -f "$PINNED_KEY_FILE" 2>/dev/null | awk '{print $2}')
if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "[SECURITY ERROR] Pinned host key fingerprint mismatch! Aborting." >&2
    echo "  Expected: $EXPECTED_FINGERPRINT" >&2
    echo "  Actual:   $ACTUAL_FINGERPRINT" >&2
    exit 1
fi

mkdir -p "$(dirname "$KNOWN_HOSTS_FILE")"
PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

echo "Connecting to Xiaomi CR8808 Ver.B (RA82) and executing pure in-memory Class R0 manifest..."

sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  "${ROUTER_USER}@${ROUTER_IP}" "sh -s" << 'EOF' | sh "$SANITIZER" > "$OUTPUT_FILE"
echo "================================================================================"
echo "R0-01: /proc/cpuinfo"
echo "================================================================================"
cat /proc/cpuinfo || true

echo "================================================================================"
echo "R0-02: /proc/meminfo"
echo "================================================================================"
cat /proc/meminfo || true

echo "================================================================================"
echo "R0-03: /proc/mtd"
echo "================================================================================"
cat /proc/mtd || true

echo "================================================================================"
echo "R0-04: dmesg switch/yt/phy/motorcomm/qca/nss"
echo "================================================================================"
dmesg | grep -i -E "switch|yt|phy|motorcomm|qca|nss" | tail -n 40 || true

echo "================================================================================"
echo "R0-05: /proc/smi (Switch Registers)"
echo "================================================================================"
[ -e /proc/smi ] && cat /proc/smi 2>/dev/null | head -n 30 || echo "smi read error or not present"

echo "================================================================================"
echo "R0-06: NVRAM Boot Flags"
echo "================================================================================"
echo "model: $(nvram get model)"
echo "flag_boot_rootfs: $(nvram get flag_boot_rootfs)"
echo "flag_boot_success: $(nvram get flag_boot_success)"
echo "flag_last_success: $(nvram get flag_last_success)"

echo "================================================================================"
echo "R0-07: ubus call system board"
echo "================================================================================"
ubus call system board || true

echo "================================================================================"
echo "R0-08: lsmod yt/qca/nss"
echo "================================================================================"
lsmod | grep -E "yt|qca|nss" || true

echo "================================================================================"
echo "R0-09: Wi-Fi Operating Mode & iwconfig"
echo "================================================================================"
uci show wireless | grep -E "channel|band|htmode|disabled" || true
iwconfig 2>/dev/null | grep -E "IEEE|Mode|Frequency|Bit Rate|Link Quality" || true

echo "================================================================================"
echo "R0-10: IP Addr & IP Route"
echo "================================================================================"
ip -4 addr show || true
ip -4 route show || true

echo "================================================================================"
echo "R0-11: Process Memory Taxonomy (/proc/<pid>/status)"
echo "================================================================================"
for name in wg_server messagingagent trafficd cab_meshd smartcontroller; do
    pids=$(pidof "$name" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            echo "--- Process: $name (PID $pid) ---"
            cat "/proc/$pid/status" 2>/dev/null | grep -E "^(Name|VmSize|VmRSS|RssAnon|RssFile):" || true
        done
    else
        echo "--- Process: $name (Not Running) ---"
    fi
done

echo "================================================================================"
echo "R0-12: Time-Bounded CPU & SoftIRQ Delta Profiling (Pure In-Memory Stream)"
echo "================================================================================"
(
    echo "=== T1 ==="
    cat /proc/stat
    cat /proc/softirqs
    sleep 10
    echo "=== T2 ==="
    cat /proc/stat
    cat /proc/softirqs
) | awk -v dur=10 '
BEGIN { phase = 0 }
/^=== T1 ===/ { phase = 1; next }
/^=== T2 ===/ { phase = 2; next }
phase == 1 {
    if ($1 ~ /^cpu[0-9]/) {
        c = $1
        u1[c]=$2; n1[c]=$3; s1[c]=$4; i1[c]=$5; w1[c]=$6; x1[c]=$7; y1[c]=$8; z1[c]=$9
    }
    if ($1 ~ /NET_RX:/) {
        rx1_0 = $2; rx1_1 = $3
    }
}
phase == 2 {
    if ($1 ~ /^cpu[0-9]/) {
        c = $1
        u2[c]=$2; n2[c]=$3; s2[c]=$4; i2[c]=$5; w2[c]=$6; x2[c]=$7; y2[c]=$8; z2[c]=$9
    }
    if ($1 ~ /NET_RX:/) {
        rx2_0 = $2; rx2_1 = $3
    }
}
END {
    printf("\n--- CPU UTILIZATION (10s delta) ---\n")
    printf("%-8s %-12s %-12s %-12s %-12s %-12s\n", "Core", "Total%", "User%", "System%", "SoftIRQ%", "Idle%")
    for (c in u1) {
        tot = (u2[c]-u1[c]) + (n2[c]-n1[c]) + (s2[c]-s1[c]) + (i2[c]-i1[c]) + (w2[c]-w1[c]) + (x2[c]-x1[c]) + (y2[c]-y1[c]) + (z2[c]-z1[c])
        if (tot > 0) {
            act = tot - (i2[c]-i1[c]) - (w2[c]-w1[c])
            printf("%-8s %-12.2f %-12.2f %-12.2f %-12.2f %-12.2f\n", 
                   c, (act/tot)*100, ((u2[c]-u1[c])/tot)*100, ((s2[c]-s1[c])/tot)*100, ((y2[c]-y1[c])/tot)*100, ((i2[c]-i1[c])/tot)*100)
        }
    }
    d0 = (rx2_0 - rx1_0); d1 = (rx2_1 - rx1_1); tot_rx = d0 + d1
    printf("\n--- NET_RX SOFTIRQ (10s delta) ---\n")
    printf("CPU0 NET_RX Delta: %d events (%.1f/sec)\n", d0, d0/dur)
    printf("CPU1 NET_RX Delta: %d events (%.1f/sec)\n", d1, d1/dur)
    if (tot_rx > 0) {
        printf("Current Window Distribution: CPU0 = %.1f%%, CPU1 = %.1f%%\n", (d0/tot_rx)*100, (d1/tot_rx)*100)
    } else {
        printf("Current Window Distribution: 0 packets processed in software path.\n")
    }
}'

echo "================================================================================"
echo "R0-13: Listening Sockets (netstat)"
echo "================================================================================"
netstat -tlpn 2>/dev/null | grep -E "56789|51820|53" || true

echo "================================================================================"
echo "R0-14: NSS Hardware Acceleration Statistics"
echo "================================================================================"
cat /sys/kernel/debug/qca-nss-drv/stats/ipv4 2>/dev/null | head -n 35 || echo "NSS stats not available"
EOF

echo "Pure In-Memory Class R0 Live Baseline Audit complete. Sanitized report saved to: $OUTPUT_FILE"
