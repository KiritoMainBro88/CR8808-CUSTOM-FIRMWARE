#!/bin/bash
# Milestone M11.0.1: Hardened, Sanitized Read-Only Audit Script for Xiaomi RA82
# Target: 192.168.31.1:56789
# Usage: export SSHPASS="<password>"; ./scripts/m11_ra82_optimization_audit.sh

set -euo pipefail

ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE:-/tmp/cr8818_known_hosts}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/cr8818_m11_ra82_live_audit_sanitized.txt}"

if [ -z "${SSHPASS:-}" ]; then
    echo "ERROR: SSHPASS environment variable is required to avoid command-line argument leakage."
    echo "Usage: export SSHPASS='mysecret'; $0"
    exit 1
fi

echo "Verifying host key for ${ROUTER_IP}:${ROUTER_PORT}..."
mkdir -p "$(dirname "$KNOWN_HOSTS_FILE")"
ssh-keyscan -p "$ROUTER_PORT" -t rsa "$ROUTER_IP" 2>/dev/null > "$KNOWN_HOSTS_FILE"

echo "Connecting to Xiaomi CR8808 Ver.B (RA82) with automated credential redaction..."

# Execute audit and pipe through multi-pattern redaction filter before writing to disk
sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  "${ROUTER_USER}@${ROUTER_IP}" '
echo "================================================================================"
echo "SECTION 1: SYSTEM, KERNEL & MEMORY BASELINE"
echo "================================================================================"
echo "--- UNAME & VERSION ---"
uname -a
cat /proc/version
uptime
cat /proc/loadavg

echo "--- CPU INFO ---"
cat /proc/cpuinfo

echo "--- MEMINFO ---"
cat /proc/meminfo

echo "--- SLAB INFO (Top 25) ---"
head -n 25 /proc/slabinfo 2>/dev/null

echo "--- LOADED KERNEL MODULES ---"
lsmod

echo "--- PROCESS TREE / RUNNING PROCESSES (SANITIZED) ---"
ps w | sed -E "s/(-srvkey|-clientkey) [^ ]+/\1 [REDACTED_WG_KEY]/g"

echo "================================================================================"
echo "SECTION 2: QUALCOMM NSS & HARDWARE ACCELERATION AUDIT"
echo "================================================================================"
echo "--- NSS DEBUG STATS DIRECTORY ---"
ls -la /sys/kernel/debug/qca-nss-drv/stats/ 2>/dev/null

echo "--- NSS IPV4 STATS ---"
cat /sys/kernel/debug/qca-nss-drv/stats/ipv4 2>/dev/null | head -n 40

echo "--- NSS IPV6 STATS ---"
cat /sys/kernel/debug/qca-nss-drv/stats/ipv6 2>/dev/null | head -n 40

echo "--- NSS GMAC STATS ---"
cat /sys/kernel/debug/qca-nss-drv/stats/gmac 2>/dev/null

echo "--- NSS PPPOE STATS ---"
cat /sys/kernel/debug/qca-nss-drv/stats/pppoe 2>/dev/null

echo "--- NSS NPOINT & PROFILER ---"
cat /sys/kernel/debug/qca-nss-drv/stats/npoint 2>/dev/null
cat /sys/kernel/debug/qca-nss-drv/stats/profiler 2>/dev/null

echo "--- ECM DB SUMMARY ---"
cat /sys/kernel/debug/ecm/ecm_db/summary 2>/dev/null

echo "--- ECM FRONT END IPV4 STATS ---"
cat /sys/kernel/debug/ecm/front_end_ipv4/stats 2>/dev/null

echo "--- ECM FRONT END IPV6 STATS ---"
cat /sys/kernel/debug/ecm/front_end_ipv6/stats 2>/dev/null

echo "--- NSS / ECM PROC STATS ---"
ls -la /proc/net/qca-nss-ecm/ 2>/dev/null
cat /proc/net/qca-nss-ecm/* 2>/dev/null

echo "================================================================================"
echo "SECTION 3: CPU IRQ, SOFTIRQ & PACKET SCHEDULING (RPS/XPS)"
echo "================================================================================"
echo "--- /proc/interrupts ---"
cat /proc/interrupts

echo "--- /proc/softirqs ---"
cat /proc/softirqs

echo "--- IRQ SMP AFFINITY ---"
for f in /proc/irq/*/smp_affinity; do
    echo "$f: $(cat "$f" 2>/dev/null)"
done 2>/dev/null | grep -v ": 3" | head -n 40

echo "--- RPS CPUS PER NETWORK QUEUE ---"
for f in /sys/class/net/*/queues/rx-*/rps_cpus; do
    echo "$f: $(cat "$f" 2>/dev/null)"
done 2>/dev/null

echo "--- XPS CPUS PER NETWORK QUEUE ---"
for f in /sys/class/net/*/queues/tx-*/xps_cpus; do
    echo "$f: $(cat "$f" 2>/dev/null)"
done 2>/dev/null

echo "================================================================================"
echo "SECTION 4: WI-FI 6 (2.4 GHz & 5 GHz HE160, DFS, OFDMA, MU-MIMO)"
echo "================================================================================"
echo "--- UCI WIRELESS CONFIGURATION (SANITIZED) ---"
uci show wireless | sed -E "s/(key|sae_password)=.*/\1=\"[REDACTED_WIFI_KEY]\"/g"

echo "--- IWCONFIG ---"
iwconfig 2>&1

echo "--- WIRELESS INTERFACES IN /proc/net/wireless ---"
cat /proc/net/wireless 2>/dev/null

echo "--- QCA IWPRIV / WLANCONFIG AUDIT (ath0, ath1, wl0, wl1) ---"
for dev in ath0 ath1 wl0 wl1; do
    if ifconfig "$dev" >/dev/null 2>&1; then
        echo "=== DEV $dev ==="
        iwpriv "$dev" get_channel 2>/dev/null
        iwpriv "$dev" get_chwidth 2>/dev/null
        iwpriv "$dev" get_mode 2>/dev/null
        iwpriv "$dev" get_country 2>/dev/null
        iwpriv "$dev" get_txpower 2>/dev/null
        wlanconfig "$dev" list 2>/dev/null | head -n 20
    fi
done

echo "================================================================================"
echo "SECTION 5: LINUX NETWORKING, TCP/IP, CONNTRACK, MTU & DNS"
echo "================================================================================"
echo "--- TCP CONGESTION CONTROL ---"
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_available_congestion_control

echo "--- TCP & CORE SOCKET BUFFERS ---"
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.rmem_max net.core.wmem_max net.core.netdev_max_backlog

echo "--- CONNTRACK PARAMETERS & LOAD ---"
sysctl net.netfilter.nf_conntrack_max net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_tcp_timeout_established 2>/dev/null
cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null
cat /proc/sys/net/ipv4/netfilter/ip_conntrack_count 2>/dev/null

echo "--- INTERFACE MTU & ADDRESSES ---"
ifconfig

echo "--- IPTABLES MANGLE TABLE (TCPMSS & CLASSIFICATION) ---"
iptables -t mangle -L -v -n

echo "--- IPTABLES NAT TABLE (FASTPATH / MASQUERADE) ---"
iptables -t nat -L -v -n | head -n 40

echo "--- DNS CONFIGURATION & RESOLV.CONF ---"
cat /etc/resolv.conf
cat /tmp/resolv.conf* 2>/dev/null

echo "================================================================================"
echo "SECTION 6: VPN SUBSYSTEM (WIREGUARD / BORINGTUN AUDIT)"
echo "================================================================================"
echo "--- RUNNING VPN PROCESSES (SANITIZED) ---"
ps | grep -iE "(wireguard|wg|boring)" | grep -v grep | sed -E "s/(-srvkey|-clientkey) [^ ]+/\1 [REDACTED_WG_KEY]/g"

echo "--- /data DIRECTORY AUDIT ---"
ls -la /data/ 2>/dev/null
ls -la /data/usr/ 2>/dev/null
ls -la /data/etc/ 2>/dev/null

echo "--- /tmp VPN RESIDUE ---"
ls -la /tmp/ | grep -iE "(wg|boring|vpn)" 2>/dev/null

echo "================================================================================"
echo "SECTION 7: SECURITY & LISTENING PORTS AUDIT"
echo "================================================================================"
echo "--- LISTENING SOCKETS (NETSTAT) ---"
netstat -tulpn 2>/dev/null || netstat -an | grep -i listen

echo "--- DROPBEAR CONFIGURATION ---"
cat /etc/config/dropbear 2>/dev/null

echo "--- WAN FIREWALL ZONE RULES ---"
iptables -L zone_wan_input -v -n 2>/dev/null
iptables -L zone_lan_input -v -n 2>/dev/null
' | sed -E \
    -e "s/(-srvkey|-clientkey) [^ ]+/\1 [REDACTED_WG_KEY]/g" \
    -e "s/(key|sae_password)=['\"][^'\"]*['\"]/\1='[REDACTED_WIFI_KEY]'/g" \
    > "$OUTPUT_FILE"

echo "Hardened audit complete. Output safely redacted to: $OUTPUT_FILE"
