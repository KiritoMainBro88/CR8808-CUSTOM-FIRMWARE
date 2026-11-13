#!/bin/sh
# performance/benchmarks/he160_wifi_profiler.sh
# Milestone M12: Read-Only Wi-Fi 6 (QCN6102 HE160 + IPQ5018 2.4G) Telemetry & Latency Profiler
# Advances WIFI-002 / WIFI-003 measurement readiness with ZERO router state mutations.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_KEY_FILE="${HOST_KEY_FILE:-${SCRIPT_DIR}/../../config/cr8818_host_key.pub}"

ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
SSH_PORT="${SSH_PORT:-56789}"
SSH_USER="${SSH_USER:-root}"
DURATION="${DURATION:-3}"
IPERF_TARGET="${IPERF_TARGET:-}"
MOCK_DIR=""
DRY_RUN=0
JSON_OUT=0

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
  --target <ip>        Router management IP (default: 192.168.31.1)
  --ssh-port <port>    Dropbear SSH port (default: 56789)
  --duration <sec>     PCIe DMA IRQ sampling window in seconds (default: 3)
  --iperf-target <ip>  Optional iperf3 server for loaded bufferbloat measurement
  --host-key <file>    Pinned host public key (default: config/cr8818_host_key.pub)
  --mock-dir <dir>     Hermetic mock root/bin directory for PC/WSL2 testing
  --dry-run            Print planned read-only probes without SSH/network calls
  --json               Emit structured JSON report
  -h, --help           Show help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --target|-t) shift; ROUTER_IP="${1:-}"; [ -n "$ROUTER_IP" ] || exit 1 ;;
        --ssh-port) shift; SSH_PORT="${1:-}"; [ -n "$SSH_PORT" ] || exit 1 ;;
        --duration|-d) shift; DURATION="${1:-}"; [ -n "$DURATION" ] || exit 1 ;;
        --iperf-target) shift; IPERF_TARGET="${1:-}"; [ -n "$IPERF_TARGET" ] || exit 1 ;;
        --host-key) shift; HOST_KEY_FILE="${1:-}"; [ -n "$HOST_KEY_FILE" ] || exit 1 ;;
        --mock-dir) shift; MOCK_DIR="${1:-}"; [ -n "$MOCK_DIR" ] || exit 1 ;;
        --dry-run) DRY_RUN=1 ;;
        --json|-j) JSON_OUT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[HE160 ERROR] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

if [ -n "$MOCK_DIR" ]; then
    [ -d "${MOCK_DIR}/bin" ] && PATH="${MOCK_DIR}/bin:${PATH}"
    export PATH
fi

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

run_pinned_ssh() {
    _cmd="$1"
    if [ -n "$MOCK_DIR" ] && [ -x "${MOCK_DIR}/bin/ssh" ]; then
        ssh -p "$SSH_PORT" "${SSH_USER}@${ROUTER_IP}" "$_cmd"
        return $?
    fi
    [ -f "$HOST_KEY_FILE" ] || {
        echo "[HE160 ERROR] Pinned host key missing: $HOST_KEY_FILE" >&2
        return 1
    }
    _kh=$(mktemp /tmp/he160_kh.XXXXXX)
    _pub=$(head -n 1 "$HOST_KEY_FILE")
    printf '%s %s\n[%s]:%s %s\n' "$ROUTER_IP" "$_pub" "$ROUTER_IP" "$SSH_PORT" "$_pub" > "$_kh"
    _rc=0
    if [ -n "${SSHPASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
        sshpass -e ssh -p "$SSH_PORT" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$_kh" \
            -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa \
            -o ConnectTimeout=5 "${SSH_USER}@${ROUTER_IP}" "$_cmd" || _rc=$?
    else
        ssh -p "$SSH_PORT" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$_kh" \
            -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa \
            -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${ROUTER_IP}" "$_cmd" || _rc=$?
    fi
    rm -f "$_kh"
    return "$_rc"
}

sum_irq_cols() {
    # Extract CPU0 and CPU1 counts for named IRQ from /proc/interrupts block
    _block="$1"
    _irq_name="$2"
    printf '%s\n' "$_block" | awk -v name="$_irq_name" '
        $NF == name {
            c0 = ($2 ~ /^[0-9]+$/) ? $2 : 0
            c1 = ($3 ~ /^[0-9]+$/) ? $3 : 0
            printf "%s %s\n", c0, c1
            found = 1
            exit
        }
        END { if (!found) printf "0 0\n" }
    '
}

parse_ping_avg_loss() {
    _out="$1"
    _loss=$(printf '%s\n' "$_out" | sed -n 's/.*, *\([0-9.]*\)% packet loss.*/\1/p' | head -n 1)
    _avg=$(printf '%s\n' "$_out" | grep -E '^(rtt|round-trip)' | awk '{print $4}' | cut -d'/' -f2 | head -n 1)
    printf '%s %s\n' "${_avg:-null}" "${_loss:-100}"
}

if [ "$DRY_RUN" -eq 1 ]; then
    cat << EOF
DRY-RUN: CR8808 Ver.B QCN6102 HE160 Read-Only Profiler
  Target Router   : ${SSH_USER}@${ROUTER_IP}:${SSH_PORT} (pinned key: ${HOST_KEY_FILE})
  Zero Writes     : Strictly read-only 'iw', 'iwpriv get_*', 'dmesg', '/proc/interrupts', 'tc qdisc show'
  Sample Window   : ${DURATION}s dual-core PCIe DMA IRQ delta (pci0_wlan_ce_1/ce_2/grp_dp_3/rxdma2host)
  Throughput Hook : $([ -n "$IPERF_TARGET" ] && echo "iperf3 -c ${IPERF_TARGET}" || echo "SKIPPED_NO_TARGET (no synthetic throughput reported)")
EOF
    exit 0
fi

TMP_DIR=$(mktemp -d /tmp/he160_prof.XXXXXX)
trap 'rm -rf "$TMP_DIR" 2>/dev/null || true' EXIT INT TERM

REMOTE_SCRIPT="
echo '@@IW_WL0@@'
iw dev wl0 info 2>&1 || true
echo '@@IW_WL0_STA@@'
iw dev wl0 station dump 2>&1 || true
echo '@@IWPRIV_WL0@@'
for cmd in get_chwidth get_ampdu get_amsdu get_preCACEn get_he_ul_ofdma get_txbf; do
    res=\$(iwpriv wl0 \"\$cmd\" 2>&1 || true)
    echo \"\${cmd}=>\${res}\"
done
echo '@@DMESG_DFS@@'
dmesg 2>/dev/null | grep -i -E 'pre cac|CAC_START|CAC_COMPLETED|dfs channel' | tail -n 20 || true
echo '@@QDISC@@'
tc qdisc show dev br-lan 2>&1 || true
tc qdisc show dev wl0 2>&1 || true
echo '@@IRQ_T0@@'
cat /proc/interrupts 2>/dev/null || true
sleep ${DURATION}
echo '@@IRQ_T1@@'
cat /proc/interrupts 2>/dev/null || true
echo '@@END@@'
"

RAW_TELEM="${TMP_DIR}/telem.txt"
if ! run_pinned_ssh "$REMOTE_SCRIPT" > "$RAW_TELEM"; then
    echo "[HE160 ERROR] Unable to collect read-only router telemetry from ${ROUTER_IP}:${SSH_PORT}" >&2
    exit 1
fi

extract_section() {
    _start="$1"
    _end="$2"
    awk -v s="$_start" -v e="$_end" '
        $0 == s { on=1; next }
        $0 == e { on=0; exit }
        on { print }
    ' "$RAW_TELEM"
}

IW_INFO=$(extract_section "@@IW_WL0@@" "@@IW_WL0_STA@@")
IW_STA=$(extract_section "@@IW_WL0_STA@@" "@@IWPRIV_WL0@@")
IWPRIV_SEC=$(extract_section "@@IWPRIV_WL0@@" "@@DMESG_DFS@@")
DMESG_DFS=$(extract_section "@@DMESG_DFS@@" "@@QDISC@@")
QDISC_SEC=$(extract_section "@@QDISC@@" "@@IRQ_T0@@")
IRQ_T0=$(extract_section "@@IRQ_T0@@" "@@IRQ_T1@@")
IRQ_T1=$(extract_section "@@IRQ_T1@@" "@@END@@")

WL0_CHAN=$(printf '%s\n' "$IW_INFO" | sed -n 's/^[[:space:]]*channel[[:space:]]*\([^,]*\).*/\1/p' | head -n 1)
WL0_WIDTH=$(printf '%s\n' "$IW_INFO" | sed -n 's/.*width:[[:space:]]*\([0-9]*[[:space:]]*MHz\).*/\1/p' | head -n 1)
WL0_CENTER1=$(printf '%s\n' "$IW_INFO" | sed -n 's/.*center1:[[:space:]]*\([0-9]*[[:space:]]*MHz\).*/\1/p' | head -n 1)
WL0_TXPOWER=$(printf '%s\n' "$IW_INFO" | sed -n 's/.*txpower[[:space:]]*\([0-9.]*[[:space:]]*dBm\).*/\1/p' | head -n 1)
STA_COUNT=$(printf '%s\n' "$IW_STA" | grep -c '^Station ' || true)

parse_iwpriv_val() {
    _key="$1"
    _line=$(printf '%s\n' "$IWPRIV_SEC" | grep "^${_key}=>" | head -n 1 || true)
    if printf '%s' "$_line" | grep -qiE 'Invalid command|not found|No such'; then
        echo "UNSUPPORTED_IOCTL"
    else
        _val=$(printf '%s' "$_line" | sed -n "s/.*${_key}:[[:space:]]*\([^[:space:]]*\).*/\1/p")
        echo "${_val:-UNVERIFIED}"
    fi
}

CHWIDTH_VAL=$(parse_iwpriv_val "get_chwidth")
AMPDU_VAL=$(parse_iwpriv_val "get_ampdu")
AMSDU_VAL=$(parse_iwpriv_val "get_amsdu")
PRECAC_VAL=$(parse_iwpriv_val "get_preCACEn")
ULOFDMA_VAL=$(parse_iwpriv_val "get_he_ul_ofdma")
TXBF_VAL=$(parse_iwpriv_val "get_txbf")

DFS_NOTE="NONE"
if printf '%s' "$DMESG_DFS" | grep -qi "not pre cac"; then
    DFS_NOTE="NOT_PRE_CAC_CAC_REQUIRED"
elif printf '%s' "$DMESG_DFS" | grep -qi "CAC_COMPLETED"; then
    DFS_NOTE="CAC_COMPLETED"
elif printf '%s' "$DMESG_DFS" | grep -qi "pre cac"; then
    DFS_NOTE="PRE_CAC_CLEARED"
fi

BRLAN_QDISC=$(printf '%s\n' "$QDISC_SEC" | grep 'dev br-lan' | head -n 1 | awk '{print $2}' || true)
[ -z "$BRLAN_QDISC" ] && BRLAN_QDISC=$(printf '%s\n' "$QDISC_SEC" | head -n 1 | awk '{print $2}' || true)

CPU0_WIFI_DELTA=0
CPU1_WIFI_DELTA=0
for _iname in pci0_wlan_ce_1 pci0_wlan_ce_2 pci0_wlan_grp_dp_3 rxdma2host-destination-ring-mac1; do
    read -r a0 a1 << EOF
$(sum_irq_cols "$IRQ_T0" "$_iname")
EOF
    read -r b0 b1 << EOF
$(sum_irq_cols "$IRQ_T1" "$_iname")
EOF
    [ "$b0" -ge "$a0" ] && CPU0_WIFI_DELTA=$((CPU0_WIFI_DELTA + b0 - a0))
    [ "$b1" -ge "$a1" ] && CPU1_WIFI_DELTA=$((CPU1_WIFI_DELTA + b1 - a1))
done
WIFI_IRQ_TOTAL=$((CPU0_WIFI_DELTA + CPU1_WIFI_DELTA))
if [ "$WIFI_IRQ_TOTAL" -gt 0 ]; then
    CPU0_WIFI_PCT=$(( (CPU0_WIFI_DELTA * 100) / WIFI_IRQ_TOTAL ))
    CPU1_WIFI_PCT=$(( 100 - CPU0_WIFI_PCT ))
else
    CPU0_WIFI_PCT=0
    CPU1_WIFI_PCT=0
fi

# Unloaded latency measurement
UNLOADED_OUT=$(ping -c 10 -i 0.1 -W 2 "$ROUTER_IP" 2>&1 || true)
read -r UNLOADED_AVG_MS UNLOADED_LOSS << EOF
$(parse_ping_avg_loss "$UNLOADED_OUT")
EOF

LOADED_AVG_MS="null"
THROUGHPUT_MBPS="null"
BUFFERBLOAT_DELTA_MS="null"
LOAD_STATUS="SKIPPED_NO_TARGET"

if [ -n "$IPERF_TARGET" ]; then
    if command -v iperf3 >/dev/null 2>&1; then
        _ipf_out="${TMP_DIR}/iperf3.json"
        _loaded_ping="${TMP_DIR}/loaded_ping.txt"
        ping -c 10 -i 0.2 -W 2 "$ROUTER_IP" > "$_loaded_ping" 2>&1 &
        _ppid=$!
        iperf3 -c "$IPERF_TARGET" -t 4 -P 2 -J > "$_ipf_out" 2>/dev/null || true
        wait "$_ppid" 2>/dev/null || true
        _bps=$(sed -n 's/.*"bits_per_second":[[:space:]]*\([0-9.e+]*\).*/\1/p' "$_ipf_out" | tail -n 1)
        if [ -n "$_bps" ]; then
            THROUGHPUT_MBPS=$(awk -v b="$_bps" 'BEGIN { printf "%.2f", b / 1000000 }')
            LOAD_STATUS="MEASURED"
        else
            LOAD_STATUS="IPERF3_FAILED"
        fi
        read -r LOADED_AVG_MS _ << EOF
$(parse_ping_avg_loss "$(cat "$_loaded_ping" 2>/dev/null || true)")
EOF
        if [ "$UNLOADED_AVG_MS" != "null" ] && [ "$LOADED_AVG_MS" != "null" ]; then
            BUFFERBLOAT_DELTA_MS=$(awk -v u="$UNLOADED_AVG_MS" -v l="$LOADED_AVG_MS" 'BEGIN { printf "%.2f", l - u }')
        fi
    else
        LOAD_STATUS="IPERF3_MISSING_ON_HOST"
    fi
fi

if [ "$JSON_OUT" -eq 1 ]; then
    cat << EOF
{
  "profiler": "he160_wifi_profiler",
  "router": "$(json_escape "$ROUTER_IP")",
  "sample_seconds": ${DURATION},
  "wl0": {
    "channel": "$(json_escape "${WL0_CHAN:-UNVERIFIED}")",
    "width": "$(json_escape "${WL0_WIDTH:-UNVERIFIED}")",
    "center1": "$(json_escape "${WL0_CENTER1:-UNVERIFIED}")",
    "txpower": "$(json_escape "${WL0_TXPOWER:-UNVERIFIED}")",
    "associated_stations": ${STA_COUNT:-0},
    "iwpriv_chwidth": "$(json_escape "$CHWIDTH_VAL")",
    "iwpriv_ampdu": "$(json_escape "$AMPDU_VAL")",
    "iwpriv_amsdu": "$(json_escape "$AMSDU_VAL")",
    "iwpriv_precac_en": "$(json_escape "$PRECAC_VAL")",
    "iwpriv_he_ul_ofdma": "$(json_escape "$ULOFDMA_VAL")",
    "iwpriv_txbf": "$(json_escape "$TXBF_VAL")",
    "dfs_dmesg_status": "$(json_escape "$DFS_NOTE")"
  },
  "qdisc_br_lan": "$(json_escape "${BRLAN_QDISC:-UNKNOWN}")",
  "pcie_wifi_irq_delta": {
    "cpu0": ${CPU0_WIFI_DELTA},
    "cpu1": ${CPU1_WIFI_DELTA},
    "cpu0_pct": ${CPU0_WIFI_PCT},
    "cpu1_pct": ${CPU1_WIFI_PCT}
  },
  "latency_and_throughput": {
    "load_status": "$(json_escape "$LOAD_STATUS")",
    "unloaded_rtt_avg_ms": ${UNLOADED_AVG_MS},
    "unloaded_loss_pct": ${UNLOADED_LOSS},
    "loaded_rtt_avg_ms": ${LOADED_AVG_MS},
    "bufferbloat_delta_ms": ${BUFFERBLOAT_DELTA_MS},
    "throughput_mbps": ${THROUGHPUT_MBPS}
  }
}
EOF
else
    echo "=== CR8808 QCN6102 HE160 Read-Only Profile ($ROUTER_IP) ==="
    echo "Radio wl0      : ch=${WL0_CHAN:-UNVERIFIED} width=${WL0_WIDTH:-UNVERIFIED} center=${WL0_CENTER1:-UNVERIFIED} txpower=${WL0_TXPOWER:-UNVERIFIED} sta=${STA_COUNT:-0}"
    echo "iwpriv wl0     : chwidth=${CHWIDTH_VAL} ampdu=${AMPDU_VAL} amsdu=${AMSDU_VAL} preCACEn=${PRECAC_VAL} he_ul_ofdma=${ULOFDMA_VAL} txbf=${TXBF_VAL}"
    echo "DFS dmesg      : ${DFS_NOTE} | br-lan qdisc=${BRLAN_QDISC:-UNKNOWN}"
    echo "Wi-Fi DMA IRQ  : CPU0=+${CPU0_WIFI_DELTA} (${CPU0_WIFI_PCT}%) | CPU1=+${CPU1_WIFI_DELTA} (${CPU1_WIFI_PCT}%)"
    echo "Latency/Load   : unloaded=${UNLOADED_AVG_MS}ms (loss ${UNLOADED_LOSS}%) | loaded=${LOADED_AVG_MS}ms | delta=${BUFFERBLOAT_DELTA_MS}ms | thrpt=${THROUGHPUT_MBPS} Mbps (${LOAD_STATUS})"
fi
