#!/bin/bash
# scripts/m12_audit_collector.sh
# Milestone M12: Live Router Architecture & Performance Baseline Collector
# Target: Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK @ 192.168.31.1:56789)
#
# Boundaries: ZERO router writes | ZERO uploads | 100% In-Memory Stream | Pinned Host Key

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"

PINNED_KEY_FILE="${SCRIPT_DIR}/config/cr8818_host_key.pub"
EXPECTED_FINGERPRINT="${EXPECTED_FINGERPRINT:-SHA256:BwYCFt/UPVQ+Sj6/ZcbKf7yfTK5FqPFYB9uN7isGL64}"
SANITIZER="${SCRIPT_DIR}/scripts/sanitize_telemetry.sh"

RAW_OUTPUT_DIR="${SCRIPT_DIR}/local_raw_audit"
RAW_OUTPUT_FILE="${RAW_OUTPUT_DIR}/m12_baseline_raw.txt"
SANITIZED_OUTPUT_FILE="${SCRIPT_DIR}/reports/M12_BASELINE_SANITIZED.txt"

if [ -z "${SSHPASS:-}" ]; then
    echo "ERROR: SSHPASS environment variable is not set." >&2
    exit 1
fi

if [ ! -f "$PINNED_KEY_FILE" ]; then
    echo "ERROR: Pinned key file $PINNED_KEY_FILE not found." >&2
    exit 1
fi

ACTUAL_FINGERPRINT=$(ssh-keygen -l -f "$PINNED_KEY_FILE" 2>/dev/null | awk '{print $2}')
if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "[SECURITY ERROR] Pinned host key mismatch! Aborting." >&2
    exit 1
fi

KNOWN_HOSTS_DIR="$(mktemp -d /tmp/cr8818_m12_ssh.XXXXXX)"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_DIR}/known_hosts"
trap 'rm -rf "$KNOWN_HOSTS_DIR"' EXIT

PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

mkdir -p "$RAW_OUTPUT_DIR"
chmod 700 "$RAW_OUTPUT_DIR"

echo "Host key verified ($EXPECTED_FINGERPRINT)."
echo "Executing M12 Read-Only In-Memory Baseline Audit on $ROUTER_IP:$ROUTER_PORT..."

TEMP_RAW="$(mktemp "${RAW_OUTPUT_DIR}/.tmp_m12_raw.XXXXXX")"

set +e
sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -o ConnectTimeout=10 \
  "${ROUTER_USER}@${ROUTER_IP}" "sh -s" << 'EOF' > "$TEMP_RAW"
echo "=== [M12-01] SYSTEM & KERNEL IDENTIFIERS ==="
uname -a
cat /proc/version
cat /proc/cmdline
uptime

echo "=== [M12-02] BOARD & HARDWARE IDENTIFIERS ==="
ubus call system board 2>/dev/null || true
ubus call system info 2>/dev/null || true

echo "=== [M12-03] CPU ARCHITECTURE & CPUFREQ ==="
cat /proc/cpuinfo
for f in /sys/devices/system/cpu/cpu*/cpufreq/*; do
  if [ -f "$f" ]; then
    echo "$f: $(cat "$f" 2>/dev/null || true)"
  fi
done

echo "=== [M12-04] MEMORY INFO & VMSTAT ==="
free -m
cat /proc/meminfo
cat /proc/vmstat
cat /proc/buddyinfo
cat /proc/pagetypeinfo
cat /proc/zoneinfo

echo "=== [M12-05] SLAB ALLOCATIONS ==="
cat /proc/slabinfo | head -n 45

echo "=== [M12-06] PROCESS RESOURCE USAGE ==="
ps w
for p in /proc/[0-9]*; do
  if [ -d "$p" ]; then
    pid=$(basename "$p")
    comm=$(cat "$p/comm" 2>/dev/null || echo "unknown")
    rss=$(grep -i VmRSS "$p/status" 2>/dev/null | awk '{print $2}' || true)
    size=$(grep -i VmSize "$p/status" 2>/dev/null | awk '{print $2}' || true)
    if [ -n "$rss" ]; then
      echo "PID $pid: $comm (VmRSS: ${rss} kB, VmSize: ${size:-0} kB)"
    fi
  fi
done | sort -k5 -n -r | head -n 30

echo "=== [M12-07] MOTORCOMM YT9215SC SWITCH & MDIO ==="
cat /proc/smi 2>/dev/null || echo "No /proc/smi"
dmesg | grep -iE "(yt|motorcomm|phy|mdio|switch|0x1d)" || true
for iface in eth0 eth1 eth2 eth3 eth4; do
  if [ -d "/sys/class/net/$iface" ]; then
    echo "--- $iface ---"
    cat "/sys/class/net/$iface/operstate" 2>/dev/null || true
    cat "/sys/class/net/$iface/carrier" 2>/dev/null || true
    cat "/sys/class/net/$iface/speed" 2>/dev/null || true
    cat "/sys/class/net/$iface/duplex" 2>/dev/null || true
    cat "/sys/class/net/$iface/address" 2>/dev/null || true
  fi
done
swconfig list 2>/dev/null || echo "swconfig not available"
if which swconfig >/dev/null 2>&1; then
  swconfig dev switch0 show 2>/dev/null || true
fi

echo "=== [M12-08] QUALCOMM NSS & HARDWARE ACCELERATION ==="
lsmod | grep -iE "(nss|qca|ecm|ppe)" || true
dmesg | grep -iE "(nss|ppe|ecm|accelerat)" | tail -n 40 || true
find /sys/kernel/debug -name "*nss*" -o -name "*ecm*" -o -name "*ppe*" 2>/dev/null | while read path; do
  if [ -f "$path" ]; then
    echo "DEBUG_PATH: $path"
    head -n 20 "$path" 2>/dev/null || true
  fi
done
if [ -d /proc/nss ]; then
  find /proc/nss -type f | while read p; do
    echo "NSS_PROC: $p"
    cat "$p" 2>/dev/null || true
  done
fi
cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || true
cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || true

echo "=== [M12-09] WI-FI ARCHITECTURE & QCN6102 5G HE160 ==="
iwconfig 2>/dev/null || true
iw dev 2>/dev/null || true
iw phy 2>/dev/null || true
uci show wireless 2>/dev/null || true
for wl in wl0 wl1; do
  if [ -d "/sys/class/net/$wl" ]; then
    echo "--- $wl queues & txqueuelen ---"
    cat "/sys/class/net/$wl/tx_queue_len" 2>/dev/null || true
    ls -l "/sys/class/net/$wl/queues/" 2>/dev/null || true
  fi
done
iwpriv 2>/dev/null || echo "iwpriv not available or no permissions"
iwpriv wl0 get_country 2>/dev/null || true
iwpriv wl1 get_country 2>/dev/null || true
iwpriv wl1 get_rate 2>/dev/null || true

echo "=== [M12-10] INTERRUPT & SOFTIRQ DISTRIBUTION (SNAPSHOT 1) ==="
cat /proc/interrupts
echo "--- /proc/softirqs ---"
cat /proc/softirqs
echo "--- /proc/net/softnet_stat ---"
cat /proc/net/softnet_stat

echo "=== [M12-11] 5-SECOND DELTA SAMPLING ==="
sleep 5
echo "--- DELTA /proc/interrupts ---"
cat /proc/interrupts
echo "--- DELTA /proc/softirqs ---"
cat /proc/softirqs
echo "--- DELTA /proc/net/softnet_stat ---"
cat /proc/net/softnet_stat

echo "=== [M12-12] RPS, RFS & SMP AFFINITIES ==="
for q in /sys/class/net/*/queues/rx-*/rps_cpus; do
  if [ -f "$q" ]; then
    echo "$q: $(cat "$q" 2>/dev/null || true)"
  fi
done
for q in /sys/class/net/*/queues/rx-*/rps_flow_cnt; do
  if [ -f "$q" ]; then
    echo "$q: $(cat "$q" 2>/dev/null || true)"
  fi
done
echo "rps_sock_flow_entries: $(cat /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true)"
for irq in /proc/irq/*/smp_affinity; do
  if [ -f "$irq" ]; then
    echo "$irq: $(cat "$irq" 2>/dev/null || true)"
  fi
done

echo "=== [M12-13] NETWORK QUEUES & TCP TUNING PARAMETERS ==="
sysctl -a 2>/dev/null | grep -E "net\.(core|ipv4\.(tcp|ip_local|neigh))" || true
tc qdisc show 2>/dev/null || true

echo "=== [M12-14] INTERFACE STATISTICS & DROPS ==="
ip -s link
cat /proc/net/dev

echo "=== [M12-15] END OF AUDIT ==="
EOF
SSH_EXIT=$?
set -e

if [ $SSH_EXIT -ne 0 ]; then
    echo "SSH execution failed with exit code $SSH_EXIT" >&2
    rm -f "$TEMP_RAW"
    exit $SSH_EXIT
fi

mv "$TEMP_RAW" "$RAW_OUTPUT_FILE"
chmod 600 "$RAW_OUTPUT_FILE"
echo "Raw audit saved to $RAW_OUTPUT_FILE (mode 600)"

if [ -f "$SANITIZER" ]; then
    sh "$SANITIZER" < "$RAW_OUTPUT_FILE" > "$SANITIZED_OUTPUT_FILE"
    echo "Sanitized audit report saved to $SANITIZED_OUTPUT_FILE"
else
    echo "Warning: Sanitizer not found at $SANITIZER"
fi

echo "Audit collection complete!"
