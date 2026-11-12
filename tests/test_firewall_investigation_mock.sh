#!/bin/bash
# tests/test_firewall_investigation_mock.sh
# Comprehensive Mock Test Suite for Class R0 Firewall Investigation Pipeline
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Tests Covered:
# 1. Preflight authorization gate check
# 2. Host key tampering / fingerprint mismatch detection
# 3. SSH connection failure & old report retention
# 4. Audit execution: COMPLETE (0/9 failures)
# 5. Audit execution: PARTIAL (e.g., 2/9 failures)
# 6. Audit execution: FAILED (9/9 failures)
# 7. Sanitizer failure & old report retention
# 8. Verification of atomic file creation (no temp leaks in target dir)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/m11_fw_mock_test.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "=== M11.1.0.5 FIREWALL INVESTIGATION MOCK TEST SUITE ==="
echo "Test Sandbox: $TEST_DIR"

MOCK_BIN_DIR="${TEST_DIR}/bin"
mkdir -p "$MOCK_BIN_DIR"
MOCK_REPORT="${TEST_DIR}/reports/test_firewall_report.txt"
mkdir -p "${TEST_DIR}/reports"

# Helper to create mock SSH wrapper
MOCK_SSH="${TEST_DIR}/mock_ssh.sh"
cat << 'MOCK_EOF' > "$MOCK_SSH"
#!/bin/bash
# Mock SSH runner
MODE="${MOCK_SSH_MODE:-success}"

if [ "$MODE" = "fail_connect" ]; then
    echo "ssh: connect to host 192.168.31.1 port 56789: Connection refused" >&2
    exit 255
fi

# In success / partial / failed mode, execute the stdin heredoc
# using customized mock tools according to MOCK_SSH_MODE
export PATH="${MOCK_TOOLS_DIR}:${PATH}"
sh -s
MOCK_EOF
chmod +x "$MOCK_SSH"

# Create mock tools directory
MOCK_TOOLS_DIR="${TEST_DIR}/mock_tools"
mkdir -p "$MOCK_TOOLS_DIR"

# Common mock commands for the 9 sections:
# ip, iptables, ip6tables, uci, netstat, head
cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/ip"
#!/bin/sh
if [ "${MOCK_FAIL_IP:-0}" = "1" ]; then exit 1; fi
echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN"
echo "    inet 127.0.0.1/8 scope host lo"
echo "    inet6 ::1/128 scope host"
echo "2: br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
echo "    inet 192.168.31.1/24 brd 192.168.31.255 scope global br-lan"
echo "    inet6 2001:db8:beef::1/64 scope global dynamic"
echo "3: eth4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
echo "    inet 192.168.100.55/24 brd 192.168.100.255 scope global eth4"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/ip"

cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/iptables"
#!/bin/sh
if [ "${MOCK_FAIL_IPTABLES:-0}" = "1" ]; then exit 1; fi
echo "-P INPUT ACCEPT"
echo "-P FORWARD DROP"
echo "-P OUTPUT ACCEPT"
echo "-A INPUT -p tcp -m tcp --dport 56789 -j ACCEPT"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/iptables"

cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/ip6tables"
#!/bin/sh
if [ "${MOCK_FAIL_IP6TABLES:-0}" = "1" ]; then exit 1; fi
echo "-P INPUT ACCEPT"
echo "-P FORWARD DROP"
echo "-P OUTPUT ACCEPT"
echo "-A INPUT -p tcp -m tcp --dport 56789 -j ACCEPT"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/ip6tables"

cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/uci"
#!/bin/sh
if [ "${MOCK_FAIL_UCI:-0}" = "1" ]; then exit 1; fi
echo "firewall.@zone[0]=zone"
echo "firewall.@zone[0].name='lan'"
echo "firewall.@zone[0].input='ACCEPT'"
echo "firewall.@zone[1]=zone"
echo "firewall.@zone[1].name='wan'"
echo "firewall.@zone[1].input='REJECT'"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/uci"

cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/netstat"
#!/bin/sh
if [ "${MOCK_FAIL_NETSTAT:-0}" = "1" ]; then exit 1; fi
echo "tcp 0 0 0.0.0.0:56789 0.0.0.0:* LISTEN 1042/dropbear"
echo "tcp 0 0 :::56789 :::* LISTEN 1042/dropbear"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/netstat"

cat << 'TOOL_EOF' > "${MOCK_TOOLS_DIR}/head"
#!/bin/sh
if [ "${MOCK_FAIL_HEAD:-0}" = "1" ]; then exit 1; fi
/usr/bin/head "$@"
TOOL_EOF
chmod +x "${MOCK_TOOLS_DIR}/head"

# --- [TEST 1] Preflight Authorization Gate Check ---
echo "--- [TEST 1] Preflight Authorization Gate Check ---"
set +e
AUTHORIZE_R0_FIREWALL_EXECUTION=0 \
SSHPASS="dummy" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/gate_out.txt" 2>&1
GATE_RC=$?
set -e

if [ "$GATE_RC" -ne 0 ] && grep -q "GATE BLOCKED" "${TEST_DIR}/gate_out.txt"; then
    echo "PASS: Script safely aborted when AUTHORIZE_R0_FIREWALL_EXECUTION != 1."
else
    echo "FAIL: Gate failed to block unauthorized execution! (rc=$GATE_RC)"
    cat "${TEST_DIR}/gate_out.txt"
    exit 1
fi

# --- [TEST 2] Host Key Tampering / Fingerprint Mismatch ---
echo "--- [TEST 2] Host Key Tampering / Fingerprint Mismatch ---"
FAKE_KEY="${TEST_DIR}/fake_key.pub"
ssh-keygen -q -t rsa -N "" -f "${TEST_DIR}/fake_id_rsa"
cp "${TEST_DIR}/fake_id_rsa.pub" "$FAKE_KEY"

set +e
AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
PINNED_KEY_FILE="$FAKE_KEY" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/fingerprint_out.txt" 2>&1
FP_RC=$?
set -e

if [ "$FP_RC" -ne 0 ] && grep -q "Pinned host key fingerprint mismatch" "${TEST_DIR}/fingerprint_out.txt"; then
    echo "PASS: Script safely aborted on host key fingerprint mismatch."
else
    echo "FAIL: Host key fingerprint check failed to catch mismatch! (rc=$FP_RC)"
    cat "${TEST_DIR}/fingerprint_out.txt"
    exit 1
fi

# --- [TEST 3] SSH Connection Failure & Old Report Retention ---
echo "--- [TEST 3] SSH Connection Failure & Old Report Retention ---"
echo "ORIGINAL_BASELINE_REPORT_DATA" > "$MOCK_REPORT"

set +e
AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
OUTPUT_FILE="$MOCK_REPORT" \
SSH_EXEC_CMD="$MOCK_SSH" \
MOCK_SSH_MODE="fail_connect" \
MOCK_TOOLS_DIR="$MOCK_TOOLS_DIR" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/ssh_fail_out.txt" 2>&1
SSH_FAIL_RC=$?
set -e

if [ "$SSH_FAIL_RC" -ne 0 ] && grep -q "PIPELINE ERROR" "${TEST_DIR}/ssh_fail_out.txt"; then
    echo "PASS: SSH failure returned non-zero code ($SSH_FAIL_RC)."
else
    echo "FAIL: SSH failure did not trigger PIPELINE ERROR! (rc=$SSH_FAIL_RC)"
    exit 1
fi

if grep -q "ORIGINAL_BASELINE_REPORT_DATA" "$MOCK_REPORT"; then
    echo "PASS: Existing report was strictly preserved after SSH failure."
else
    echo "FAIL: Existing report was overwritten or corrupted during SSH failure!"
    exit 1
fi

# --- [TEST 4] Audit Execution: COMPLETE (0/9 Failures) ---
echo "--- [TEST 4] Audit Execution: COMPLETE (0/9 Failures) ---"
export MOCK_FAIL_IP=0
export MOCK_FAIL_IPTABLES=0
export MOCK_FAIL_IP6TABLES=0
export MOCK_FAIL_UCI=0
export MOCK_FAIL_NETSTAT=0
export MOCK_FAIL_HEAD=0

AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
OUTPUT_FILE="$MOCK_REPORT" \
SSH_EXEC_CMD="$MOCK_SSH" \
MOCK_SSH_MODE="success" \
MOCK_TOOLS_DIR="$MOCK_TOOLS_DIR" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/audit_complete_out.txt" 2>&1

if grep -q "OVERALL INVESTIGATION STATUS: COMPLETE (0/9 failures)" "$MOCK_REPORT"; then
    echo "PASS: Audit correctly reported COMPLETE (0/9 failures)."
else
    echo "FAIL: Expected COMPLETE status not found in report!"
    cat "$MOCK_REPORT"
    exit 1
fi

# Verify sanitization ran on the output (WAN IP and IPv6 redacted, LAN preserved)
if grep -q "\[REDACTED_WAN_IP\]" "$MOCK_REPORT" && grep -q "\[REDACTED_IPV6_GUA\]" "$MOCK_REPORT"; then
    echo "PASS: Sanitization was verified active on the report output (WAN IP and IPv6 GUA redacted)."
else
    echo "FAIL: Sanitization did not redact WAN IP or IPv6 GUA in report!"
    exit 1
fi

if grep -q "192.168.31.1" "$MOCK_REPORT"; then
    echo "PASS: Router LAN subnet 192.168.31.x correctly preserved by whitelist."
else
    echo "FAIL: Router LAN subnet was unexpectedly redacted!"
    exit 1
fi

# --- [TEST 5] Audit Execution: PARTIAL (2/9 Failures) ---
echo "--- [TEST 5] Audit Execution: PARTIAL (2/9 Failures) ---"
export MOCK_FAIL_IP6TABLES=1
export MOCK_FAIL_UCI=1

AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
OUTPUT_FILE="$MOCK_REPORT" \
SSH_EXEC_CMD="$MOCK_SSH" \
MOCK_SSH_MODE="success" \
MOCK_TOOLS_DIR="$MOCK_TOOLS_DIR" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/audit_partial_out.txt" 2>&1

if grep -q "OVERALL INVESTIGATION STATUS: PARTIAL (4/9 failures)" "$MOCK_REPORT"; then
    echo "PASS: Audit correctly reported PARTIAL (4/9 failures)."
else
    echo "FAIL: Expected PARTIAL (4/9 failures) status not found in report!"
    cat "$MOCK_REPORT"
    exit 1
fi

# --- [TEST 6] Audit Execution: FAILED (9/9 Failures) ---
echo "--- [TEST 6] Audit Execution: FAILED (9/9 Failures) ---"
export MOCK_FAIL_IP=1
export MOCK_FAIL_IPTABLES=1
export MOCK_FAIL_IP6TABLES=1
export MOCK_FAIL_UCI=1
export MOCK_FAIL_NETSTAT=1
export MOCK_FAIL_HEAD=1

AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
OUTPUT_FILE="$MOCK_REPORT" \
SSH_EXEC_CMD="$MOCK_SSH" \
MOCK_SSH_MODE="success" \
MOCK_TOOLS_DIR="$MOCK_TOOLS_DIR" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/audit_failed_out.txt" 2>&1

if grep -q "OVERALL INVESTIGATION STATUS: FAILED (9/9 failures)" "$MOCK_REPORT"; then
    echo "PASS: Audit correctly reported FAILED (9/9 failures)."
else
    echo "FAIL: Expected FAILED (9/9 failures) status not found in report!"
    cat "$MOCK_REPORT"
    exit 1
fi

# Reset mock tool flags
export MOCK_FAIL_IP=0
export MOCK_FAIL_IPTABLES=0
export MOCK_FAIL_IP6TABLES=0
export MOCK_FAIL_UCI=0
export MOCK_FAIL_NETSTAT=0
export MOCK_FAIL_HEAD=0

# --- [TEST 7] Sanitizer Failure & Old Report Retention ---
echo "--- [TEST 7] Sanitizer Failure & Old Report Retention ---"
echo "PRESERVED_BEFORE_SANITIZER_CRASH" > "$MOCK_REPORT"

set +e
AUTHORIZE_R0_FIREWALL_EXECUTION=1 \
SSHPASS="dummy" \
OUTPUT_FILE="$MOCK_REPORT" \
SSH_EXEC_CMD="$MOCK_SSH" \
MOCK_SSH_MODE="success" \
MOCK_TOOLS_DIR="$MOCK_TOOLS_DIR" \
SANITIZER="/bin/false" \
bash "${SCRIPT_DIR}/scripts/m11_1_firewall_investigation.sh" > "${TEST_DIR}/sanitizer_fail_out.txt" 2>&1
SAN_FAIL_RC=$?
set -e

if [ "$SAN_FAIL_RC" -ne 0 ] && grep -q "Sanitization failed! Existing report preserved." "${TEST_DIR}/sanitizer_fail_out.txt"; then
    echo "PASS: Sanitizer failure returned non-zero code ($SAN_FAIL_RC) and logged error."
else
    echo "FAIL: Sanitizer failure did not abort correctly! (rc=$SAN_FAIL_RC)"
    cat "${TEST_DIR}/sanitizer_fail_out.txt"
    exit 1
fi

if grep -q "PRESERVED_BEFORE_SANITIZER_CRASH" "$MOCK_REPORT"; then
    echo "PASS: Existing report was strictly preserved after sanitizer failure."
else
    echo "FAIL: Existing report was corrupted on sanitizer failure!"
    exit 1
fi

# --- [TEST 8] Atomic Creation & Zero Leaked Temp Files ---
echo "--- [TEST 8] Atomic Creation & Zero Leaked Temp Files ---"
TEMP_LEAKS=$(find "${TEST_DIR}/reports" -name ".tmp_*" | wc -l)
if [ "$TEMP_LEAKS" -eq 0 ]; then
    echo "PASS: Zero temporary files leaked in output directory."
else
    echo "FAIL: Found $TEMP_LEAKS leaked temporary files in ${TEST_DIR}/reports!"
    find "${TEST_DIR}/reports" -name ".tmp_*"
    exit 1
fi

echo "=== ALL 8 FIREWALL INVESTIGATION MOCK TESTS PASSED ==="
