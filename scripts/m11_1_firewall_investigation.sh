#!/bin/bash
# scripts/m11_1_firewall_investigation.sh
# Class R0 Firewall & Dual-Stack Network Investigation Script
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# HARDENED WITH BASH PIPELINE INTEGRITY & STRICT ERROR PROPAGATION
# Strict Constraints: ZERO writes to router | Pinned Host Key Verification | Sanitized Output

set -Eeuo pipefail

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
TEMP_RAW_OUTPUT="$(mktemp /tmp/cr8818_fw_raw.XXXXXX)"
TEMP_SANITIZED="$(mktemp /tmp/cr8818_fw_san.XXXXXX)"
trap 'rm -rf "$KNOWN_HOSTS_DIR" "$TEMP_RAW_OUTPUT" "$TEMP_SANITIZED"' EXIT

PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

echo "Host key verified ($EXPECTED_FINGERPRINT). Connecting to CR8808 Ver.B..."

# Step 3: Execute SSH and capture raw output into temporary file first
# Using Bash set -e to ensure SSH failure aborts before touching destination report
if ! sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -o ConnectTimeout=5 \
  "${ROUTER_USER}@${ROUTER_IP}" "sh -s" << 'EOF' > "$TEMP_RAW_OUTPUT"
TOTAL_SECTIONS=9
SECTION_FAILURES=0

run_cmd() {
    SEC_ID="$1"
    SEC_NAME="$2"
    shift 2
    echo "================================================================================"
    echo "[$SEC_ID] $SEC_NAME"
    echo "================================================================================"
    if "$@"; then
        echo "[$SEC_ID STATUS: SUCCESS]"
    else
        echo "[$SEC_ID STATUS: FAILED - exit code $?]"
        SECTION_FAILURES=$((SECTION_FAILURES + 1))
    fi
}

# FW-01: IPv4 Address & Routing Table
run_cmd "FW-01" "IPv4 Address & Routing Table" sh -c "ip -4 addr show && ip -4 route show table all"

# FW-02: IPv6 Address, Routing Table & Interface Counters
run_cmd "FW-02" "IPv6 Address, Routing Table & Interface Counters" sh -c "ip -6 addr show && ip -6 route show table all && cat /proc/net/if_inet6"

# FW-03: Full iptables Filter Table Rules
run_cmd "FW-03" "Full iptables Filter Table Rules (-S and -nvL)" sh -c "iptables -S && iptables -t filter -nvL"

# FW-04: Full ip6tables Filter Table Rules
run_cmd "FW-04" "Full ip6tables Filter Table Rules (-S and -nvL)" sh -c "ip6tables -S && ip6tables -t filter -nvL"

# FW-05: IPv4 WAN Ingress Chains
run_cmd "FW-05" "IPv4 WAN Ingress Chains (zone_wan_input & input_wan_rule)" sh -c "iptables -nvL zone_wan_input && iptables -nvL input_wan_rule"

# FW-06: IPv6 WAN Ingress Chains
run_cmd "FW-06" "IPv6 WAN Ingress Chains (zone_wan_input & input_wan_rule)" sh -c "ip6tables -nvL zone_wan_input && ip6tables -nvL input_wan_rule"

# FW-07: UCI Firewall Zone Configuration
run_cmd "FW-07" "UCI Firewall Zone Configuration" sh -c "uci show firewall | grep -E 'zone|wan|input|dropbear'"

# FW-08: Dropbear Sockets & UCI Settings
run_cmd "FW-08" "Dropbear Sockets & UCI Settings" sh -c "netstat -tlpn | grep dropbear && uci show dropbear"

# FW-09: Kernel TCP Sockets
run_cmd "FW-09" "Kernel TCP Sockets (/proc/net/tcp & tcp6)" sh -c "head -n 25 /proc/net/tcp && head -n 25 /proc/net/tcp6"

echo "================================================================================"
if [ "$SECTION_FAILURES" -eq 0 ]; then
    echo "[OVERALL INVESTIGATION STATUS: COMPLETE (0/$TOTAL_SECTIONS failures)]"
elif [ "$SECTION_FAILURES" -lt "$TOTAL_SECTIONS" ]; then
    echo "[OVERALL INVESTIGATION STATUS: PARTIAL ($SECTION_FAILURES/$TOTAL_SECTIONS failures)]"
else
    echo "[OVERALL INVESTIGATION STATUS: FAILED ($SECTION_FAILURES/$TOTAL_SECTIONS failures)]"
fi
echo "================================================================================"
EOF
then
    echo "[PIPELINE ERROR] SSH command failed or timed out! Aborting without modifying existing report." >&2
    exit 1
fi

# Step 4: Stream sanitized output to temporary destination and verify exit status
if ! bash "$SANITIZER" < "$TEMP_RAW_OUTPUT" > "$TEMP_SANITIZED"; then
    echo "[PIPELINE ERROR] Sanitization failed! Existing report preserved." >&2
    exit 1
fi

# Step 5: Atomic move to destination report (never leaves partial/corrupt files)
mkdir -p "$(dirname "$OUTPUT_FILE")"
mv -f "$TEMP_SANITIZED" "$OUTPUT_FILE"

echo "Class R0 Firewall Investigation complete. Sanitized report atomically saved to: $OUTPUT_FILE"
