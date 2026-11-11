#!/bin/sh
# scripts/m11_1_firewall_investigation.sh
# Class R0 Firewall & Dual-Stack Network Investigation Script
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# PC-SIDE DRAFT IMPLEMENTATION — REQUIRES EXPLICIT ARCHITECT AUTHORIZATION
# Strict Constraints: ZERO writes to router | Pinned Host Key Verification | Sanitized Output

set -eu

ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"
OUTPUT_FILE="${OUTPUT_FILE:-reports/M11_1_FIREWALL_AUDIT_RAW.txt}"
PINNED_KEY_FILE="config/cr8818_host_key.pub"
EXPECTED_FINGERPRINT="SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM"
SANITIZER="scripts/sanitize_telemetry.sh"

# Pre-flight Gate: Require explicit environment variable authorization
if [ "${AUTHORIZE_R0_FIREWALL_EXECUTION:-0}" != "1" ]; then
    echo "[GATE BLOCKED] Execution aborted: AUTHORIZE_R0_FIREWALL_EXECUTION is not set to 1."
    echo "This script is prepared on PC and requires explicit authorization from the Chief Architect."
    exit 1
fi

if [ -z "${SSHPASS:-}" ]; then
    echo "ERROR: SSHPASS environment variable is not set." >&2
    exit 1
fi

if [ ! -f "$PINNED_KEY_FILE" ]; then
    echo "ERROR: Pinned host key file $PINNED_KEY_FILE not found." >&2
    exit 1
fi

# Step 1: Validate Pinned Host Key Fingerprint
ACTUAL_FINGERPRINT=$(ssh-keygen -l -f "$PINNED_KEY_FILE" 2>/dev/null | awk '{print $2}')
if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "[SECURITY ERROR] Pinned host key fingerprint mismatch! Aborting." >&2
    exit 1
fi

# Step 2: Synthesize Verified Known Hosts File
KNOWN_HOSTS_DIR="$(mktemp -d /tmp/cr8818_ssh.XXXXXX)"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_DIR}/known_hosts"
trap 'rm -rf "$KNOWN_HOSTS_DIR"' EXIT

PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

echo "Host key verified ($EXPECTED_FINGERPRINT). Connecting to CR8808 Ver.B..."

# Step 3: Stream Interrogation Commands and Pipe through Sanitizer
sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o ConnectTimeout=5 \
  "${ROUTER_USER}@${ROUTER_IP}" "sh -s" << 'EOF' | sh "$SANITIZER" > "$OUTPUT_FILE"
echo "================================================================================"
echo "FW-01: IPv4 Address & Routing Table"
echo "================================================================================"
ip -4 addr show
ip -4 route show table all

echo "================================================================================"
echo "FW-02: IPv6 Address, Routing Table & Interface Counters"
echo "================================================================================"
ip -6 addr show 2>/dev/null || echo "IPv6 addr show not supported"
ip -6 route show table all 2>/dev/null || echo "IPv6 route show not supported"
cat /proc/net/if_inet6 2>/dev/null || echo "/proc/net/if_inet6 not present"

echo "================================================================================"
echo "FW-03: Full iptables Filter Table Rules (-S and -nvL)"
echo "================================================================================"
iptables -S 2>/dev/null || echo "iptables -S not supported"
iptables -t filter -nvL 2>/dev/null || echo "iptables -t filter -nvL failed"

echo "================================================================================"
echo "FW-04: Full ip6tables Filter Table Rules (-S and -nvL)"
echo "================================================================================"
ip6tables -S 2>/dev/null || echo "ip6tables -S not supported"
ip6tables -t filter -nvL 2>/dev/null || echo "ip6tables -t filter -nvL failed"

echo "================================================================================"
echo "FW-05: IPv4 WAN Ingress Chains (zone_wan_input & input_wan_rule)"
echo "================================================================================"
iptables -nvL zone_wan_input 2>/dev/null || echo "IPv4 zone_wan_input not present"
iptables -nvL input_wan_rule 2>/dev/null || echo "IPv4 input_wan_rule not present"

echo "================================================================================"
echo "FW-06: IPv6 WAN Ingress Chains (zone_wan_input & input_wan_rule)"
echo "================================================================================"
ip6tables -nvL zone_wan_input 2>/dev/null || echo "IPv6 zone_wan_input not present"
ip6tables -nvL input_wan_rule 2>/dev/null || echo "IPv6 input_wan_rule not present"

echo "================================================================================"
echo "FW-07: UCI Firewall Zone Configuration"
echo "================================================================================"
uci show firewall | grep -E "zone|wan|input|dropbear" || echo "UCI firewall read failed"

echo "================================================================================"
echo "FW-08: Dropbear Sockets & UCI Settings"
echo "================================================================================"
netstat -tlpn 2>/dev/null | grep dropbear || echo "No dropbear socket in netstat"
uci show dropbear 2>/dev/null || echo "UCI dropbear read failed"

echo "================================================================================"
echo "FW-09: Kernel TCP Sockets (/proc/net/tcp & tcp6)"
echo "================================================================================"
cat /proc/net/tcp 2>/dev/null | head -n 25 || echo "/proc/net/tcp not present"
cat /proc/net/tcp6 2>/dev/null | head -n 25 || echo "/proc/net/tcp6 not present"
EOF

echo "Class R0 Firewall Investigation complete. Sanitized report saved to: $OUTPUT_FILE"
