#!/bin/bash
# scripts/m11_1_r0_minimal_audit.sh
# Minimal, Strictly Read-Only SSH Investigation Script for Class R0 Firewall Audit
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Authorized by Chief Architect Directive M11.1 Step 1.5
# Strict Boundaries: ZERO writes to router | ZERO uploads | Pinned Host Key Verification
# Raw confidential output saved locally outside Git (local_raw_audit/)
# Sanitized summary saved to reports/M11_1_R0_MINIMAL_AUDIT_SANITIZED.txt

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"

PINNED_KEY_FILE="${SCRIPT_DIR}/config/cr8818_host_key.pub"
EXPECTED_FINGERPRINT="${EXPECTED_FINGERPRINT:-SHA256:BwYCFt/UPVQ+Sj6/ZcbKf7yfTK5FqPFYB9uN7isGL64}"
SANITIZER="${SCRIPT_DIR}/scripts/sanitize_telemetry.sh"

RAW_OUTPUT_DIR="${SCRIPT_DIR}/local_raw_audit"
RAW_OUTPUT_FILE="${RAW_OUTPUT_DIR}/m11_1_r0_minimal_raw.txt"
SANITIZED_OUTPUT_FILE="${SCRIPT_DIR}/reports/M11_1_R0_MINIMAL_AUDIT_SANITIZED.txt"

# Pre-flight Gate: SSHPASS must be set in environment
if [ -z "${SSHPASS:-}" ]; then
    echo "ERROR: SSHPASS environment variable is not set." >&2
    echo "Usage: export SSHPASS='...'; bash $0" >&2
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
    echo "Expected: $EXPECTED_FINGERPRINT" >&2
    echo "Actual:   $ACTUAL_FINGERPRINT" >&2
    exit 1
fi

# Step 2: Synthesize Verified Known Hosts File
KNOWN_HOSTS_DIR="$(mktemp -d /tmp/cr8818_r0_ssh.XXXXXX)"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_DIR}/known_hosts"
trap 'rm -rf "$KNOWN_HOSTS_DIR"' EXIT

PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

mkdir -p "$RAW_OUTPUT_DIR"
chmod 700 "$RAW_OUTPUT_DIR"

echo "Host key verified ($EXPECTED_FINGERPRINT)."
echo "Connecting to CR8808 Ver.B ($ROUTER_IP:$ROUTER_PORT) for strictly read-only R0 audit..."

# Step 3: Execute remote commands via stdin pipe (zero files created on router)
SSH_EXEC_CMD="${SSH_EXEC_CMD:-sshpass -e ssh}"
TEMP_RAW="$(mktemp "${RAW_OUTPUT_DIR}/.tmp_raw.XXXXXX")"

set +e
$SSH_EXEC_CMD -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -o ConnectTimeout=8 \
  "${ROUTER_USER}@${ROUTER_IP}" "sh -s" << 'EOF' > "$TEMP_RAW" 2>&1
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

# R0-FW-01: IPv4 Address & Routing Table
run_cmd "R0-FW-01" "IPv4 Address & Routing Table" sh -c "ip -4 addr show && echo '--- Routes ---' && ip -4 route show table all"

# R0-FW-02: IPv6 Address, Routing Table & Interface Counters
run_cmd "R0-FW-02" "IPv6 Address, Routing Table & Interface Counters" sh -c "ip -6 addr show && echo '--- IPv6 Routes ---' && ip -6 route show table all && echo '--- /proc/net/if_inet6 ---' && cat /proc/net/if_inet6"

# R0-FW-03: Full iptables Filter Table Rules
run_cmd "R0-FW-03" "Full iptables Filter Table Rules (-S and -nvL)" sh -c "iptables -S && echo '--- iptables -t filter -nvL ---' && iptables -t filter -nvL"

# R0-FW-04: Full ip6tables Filter Table Rules
run_cmd "R0-FW-04" "Full ip6tables Filter Table Rules (-S and -nvL)" sh -c "ip6tables -S && echo '--- ip6tables -t filter -nvL ---' && ip6tables -t filter -nvL"

# R0-FW-05: IPv4 WAN Ingress Chains
run_cmd "R0-FW-05" "IPv4 WAN Ingress Chains (zone_wan_input & input_wan_rule)" sh -c "(iptables -nvL zone_wan_input 2>/dev/null || echo 'zone_wan_input absent') && (iptables -nvL input_wan_rule 2>/dev/null || echo 'input_wan_rule absent')"

# R0-FW-06: IPv6 WAN Ingress Chains
run_cmd "R0-FW-06" "IPv6 WAN Ingress Chains (zone_wan_input & input_wan_rule)" sh -c "(ip6tables -nvL zone_wan_input 2>/dev/null || echo 'ip6tables zone_wan_input absent') && (ip6tables -nvL input_wan_rule 2>/dev/null || echo 'ip6tables input_wan_rule absent')"

# R0-FW-07: UCI Firewall Zone Configuration
run_cmd "R0-FW-07" "UCI Firewall Zone Configuration" sh -c "uci show firewall | grep -E 'zone|wan|input|dropbear'"

# R0-FW-08: Dropbear Sockets & UCI Settings
run_cmd "R0-FW-08" "Dropbear Sockets & UCI Settings" sh -c "netstat -tlpn | grep dropbear && uci show dropbear"

# R0-FW-09: Kernel TCP Sockets
run_cmd "R0-FW-09" "Kernel TCP Sockets (/proc/net/tcp & tcp6)" sh -c "echo '--- /proc/net/tcp ---' && head -n 25 /proc/net/tcp && echo '--- /proc/net/tcp6 ---' && head -n 25 /proc/net/tcp6"

echo "================================================================================"
if [ "$SECTION_FAILURES" -eq 0 ]; then
    echo "[OVERALL INVESTIGATION STATUS: COMPLETE (0/$TOTAL_SECTIONS failures)]"
    exit 0
elif [ "$SECTION_FAILURES" -lt "$TOTAL_SECTIONS" ]; then
    echo "[OVERALL INVESTIGATION STATUS: PARTIAL ($SECTION_FAILURES/$TOTAL_SECTIONS failures)]"
    exit 2
else
    echo "[OVERALL INVESTIGATION STATUS: FAILED ($SECTION_FAILURES/$TOTAL_SECTIONS failures)]"
    exit 3
fi
echo "================================================================================"
EOF
SSH_RC=$?
set -e

# Step 4: Handle Raw Output
if [ "$SSH_RC" -ne 0 ] && [ ! -s "$TEMP_RAW" ]; then
    echo "[PIPELINE ERROR] SSH connection failed (exit code $SSH_RC)." >&2
    rm -f "$TEMP_RAW"
    exit 1
fi

chmod 600 "$TEMP_RAW"
mv -f "$TEMP_RAW" "$RAW_OUTPUT_FILE"
echo "Confidential raw output saved locally outside Git: $RAW_OUTPUT_FILE (mode 600)"

# Step 5: Sanitize Output
mkdir -p "$(dirname "$SANITIZED_OUTPUT_FILE")"
bash "$SANITIZER" < "$RAW_OUTPUT_FILE" > "$SANITIZED_OUTPUT_FILE"
echo "Sanitized audit report published to: $SANITIZED_OUTPUT_FILE"

# Step 6: Verify Overall Status
if grep -q "\[OVERALL INVESTIGATION STATUS: COMPLETE" "$SANITIZED_OUTPUT_FILE"; then
    echo "Minimal R0 Audit completed successfully with status: COMPLETE."
    exit 0
elif grep -q "\[OVERALL INVESTIGATION STATUS: PARTIAL" "$SANITIZED_OUTPUT_FILE"; then
    echo "WARNING: Minimal R0 Audit completed with status: PARTIAL."
    exit 2
else
    echo "ERROR: Minimal R0 Audit completed with status: FAILED."
    exit 3
fi
