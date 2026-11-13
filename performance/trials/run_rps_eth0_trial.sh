#!/bin/sh
# performance/trials/run_rps_eth0_trial.sh
# ==============================================================================
# Controlled Single-Variable Host Orchestrator: eth0/rx-0 RPS Trial (0 -> 2 -> 0)
# Target: Xiaomi CR8808 Ver.B / RA82 v1.4.31 (192.168.31.1:56789)
#
# Responsibilities:
#   - True client-side SSH + ICMP reachability gate BEFORE, DURING, and AFTER
#   - Stages controlled_trial_runner.sh ONLY to volatile /tmp (zero flash writes)
#   - Collects Before / During / After telemetry:
#       * NET_RX CPU0/CPU1 softirqs (/proc/softirqs)
#       * NSS & ECM stats (/sys/kernel/debug/qca-nss-drv/stats/ipv4, ecm)
#       * Packet drops & softnet (/proc/net/dev eth0 & br-lan, /proc/net/softnet_stat)
#       * Memory headroom & slab (/proc/meminfo MemAvailable, Slab, SUnreclaim)
#       * Client-side ICMP RTT (Before / During / After)
#       * Optional throughput hook via --iperf-target (or HOOK_SKIPPED_NO_TARGET)
#   - Independent post-trial SSH readback verification (rps_cpus == 0)
#   - Anti-conflation guardrail: NET_RX core shift != proven throughput gain
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_LOCAL="${SCRIPT_DIR}/controlled_trial_runner.sh"
HOST_KEY_FILE="${HOST_KEY_FILE:-${SCRIPT_DIR}/../../config/cr8818_host_key.pub}"

DRY_RUN=0
AUTHORIZE_LIVE=0
MOCK_DIR=""
SSH_HOST="${SSH_HOST:-192.168.31.1}"
SSH_PORT="${SSH_PORT:-56789}"
SSH_USER="${SSH_USER:-root}"
IPERF_TARGET="${IPERF3_TARGET:-}"
MEASURE_SECONDS="${MEASURE_SECONDS:-30}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-180}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-3}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/rps_eth0_trial_reports}"
TARGET_SYSFS="/sys/class/net/eth0/queues/rx-0/rps_cpus"
REMOTE_RUNNER="/tmp/rps_eth0_trial.sh"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
  --dry-run                Print planned SSH/telemetry steps without connecting
  --authorize-live-trial   Explicit confirmation required before live router SSH run
  --mock-dir <dir>         Hermetic mock bin/env mode for PC/WSL2 E2E testing
  --iperf-target <host>    Optional iperf3 server target for Before/During/After Mbps
  --measure-seconds <N>    Active RPS=2 trial duration in seconds (default: 30)
  --watchdog-timeout <N>   Independent router watchdog timeout (default: 180)
  --ssh-host <host>        Router management host (default: 192.168.31.1)
  --ssh-port <port>        Router Dropbear SSH port (default: 56789)
  --output-dir <dir>       Report output directory (default: /tmp/rps_eth0_trial_reports)
  -h, --help               Show help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --authorize-live-trial) AUTHORIZE_LIVE=1; shift ;;
        --mock-dir) MOCK_DIR="${2:?missing --mock-dir value}"; shift 2 ;;
        --iperf-target) IPERF_TARGET="${2:?missing --iperf-target value}"; shift 2 ;;
        --measure-seconds) MEASURE_SECONDS="${2:?missing --measure-seconds value}"; shift 2 ;;
        --watchdog-timeout) WATCHDOG_TIMEOUT="${2:?missing --watchdog-timeout value}"; shift 2 ;;
        --ssh-host) SSH_HOST="${2:?missing --ssh-host value}"; shift 2 ;;
        --ssh-port) SSH_PORT="${2:?missing --ssh-port value}"; shift 2 ;;
        --output-dir) OUTPUT_DIR="${2:?missing --output-dir value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[ORCH-ERROR] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

log_info()    { echo "[ORCH-INFO]  $*"; }
log_warn()    { echo "[ORCH-WARN]  $*" >&2; }
log_err()     { echo "[ORCH-ERROR] $*" >&2; }
log_success() { echo "[ORCH-OK]    $*"; }

MANUAL_RECOVERY_CMD="ssh -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST} \"sh -c 'printf 0 > ${TARGET_SYSFS} && rm -f /tmp/trial_state/rps_trial.state'\""
LIVE_OWNER_CMD="sh performance/trials/run_rps_eth0_trial.sh --authorize-live-trial --measure-seconds ${MEASURE_SECONDS} --watchdog-timeout ${WATCHDOG_TIMEOUT}"

if [ ! -f "$RUNNER_LOCAL" ]; then
    log_err "Missing controlled trial runner: $RUNNER_LOCAL"
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "================================================================================"
    echo "DRY-RUN PLAN: CONTROLLED RPS TRIAL FOR eth0/rx-0 (ZERO ROUTER WRITES EXECUTED)"
    echo "================================================================================"
    echo "Target Router:     ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
    echo "Pinned Host Key:   ${HOST_KEY_FILE}"
    echo "Parameter Change:  ${TARGET_SYSFS} (0 -> 2 -> 0)"
    echo "Window / Watchdog: ${MEASURE_SECONDS}s measurement / ${WATCHDOG_TIMEOUT}s router watchdog"
    echo "Precondition Gate: Client ICMP ping + pinned SSH roundtrip + baseline rps_cpus==0"
    echo "During Safety:     Background client reachability monitor (SSH+ICMP every ${MONITOR_INTERVAL}s)"
    echo "Telemetry Captured:Before / During / After (NET_RX CPU0/CPU1, NSS/ECM, /proc/net/dev,"
    echo "                   /proc/net/softnet_stat, MemAvailable/Slab/SUnreclaim, ICMP RTT,"
    if [ -n "$IPERF_TARGET" ]; then
        echo "                   iperf3 throughput against ${IPERF_TARGET})"
    else
        echo "                   throughput=HOOK_SKIPPED_NO_TARGET unless --iperf-target supplied)"
    fi
    echo "Post-Trial Gate:   Independent SSH readback confirming rps_cpus==0 & clean state file"
    echo "Emergency Recovery:${MANUAL_RECOVERY_CMD}"
    echo "Owner Live Command:${LIVE_OWNER_CMD}"
    echo "================================================================================"
    exit 0
fi

if [ -n "$MOCK_DIR" ]; then
    PATH="${MOCK_DIR}/bin:${PATH}"
    export PATH
    if [ -f "${MOCK_DIR}/env.sh" ]; then
        # Load explicit mock test env variables if present
        MOCK_ENV_FILE="${MOCK_DIR}/env.sh"
        . "$MOCK_ENV_FILE"
    fi
elif [ "$AUTHORIZE_LIVE" -ne 1 ]; then
    log_err "Refusing live router trial without explicit --authorize-live-trial flag."
    echo "Dry-run preview:  sh performance/trials/run_rps_eth0_trial.sh --dry-run"
    echo "Owner live run:   ${LIVE_OWNER_CMD}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
TS_TAG=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "run")
WORK_TMP=$(mktemp -d /tmp/rps_orch_work.XXXXXX)
REPORT_TXT="${OUTPUT_DIR}/rps_eth0_trial_${TS_TAG}.txt"
REPORT_JSON="${OUTPUT_DIR}/rps_eth0_trial_${TS_TAG}.json"
KNOWN_HOSTS_TMP=""

cleanup() {
    if [ -n "${MON_PID:-}" ]; then
        kill "$MON_PID" 2>/dev/null || true
    fi
    if [ -n "${RUNNER_PID:-}" ] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        kill "$RUNNER_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK_TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Prepare pinned SSH arguments
build_ssh_opts() {
    if [ -n "$MOCK_DIR" ]; then
        echo "-p ${SSH_PORT} -o BatchMode=yes -o ConnectTimeout=5"
        return 0
    fi
    if [ ! -f "$HOST_KEY_FILE" ]; then
        log_err "Pinned host key file missing: $HOST_KEY_FILE (refusing unverified SSH)"
        return 1
    fi
    KNOWN_HOSTS_TMP="${WORK_TMP}/known_hosts"
    _key_fields=$(awk '{print $1, $2}' "$HOST_KEY_FILE" 2>/dev/null)
    if [ -z "$_key_fields" ]; then
        log_err "Invalid pinned host key format in $HOST_KEY_FILE"
        return 1
    fi
    if [ "$SSH_PORT" = "22" ]; then
        printf '%s %s\n' "$SSH_HOST" "$_key_fields" > "$KNOWN_HOSTS_TMP"
    else
        printf '[%s]:%s %s\n' "$SSH_HOST" "$SSH_PORT" "$_key_fields" > "$KNOWN_HOSTS_TMP"
    fi
    echo "-p ${SSH_PORT} -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${KNOWN_HOSTS_TMP}"
}

SSH_OPTS=$(build_ssh_opts) || exit 1

run_ssh() {
    # Word-splitting intentional on $SSH_OPTS
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "$1"
}

check_client_reachability() {
    if ! ping -c 1 -W 2 "$SSH_HOST" >/dev/null 2>&1; then
        return 1
    fi
    if ! _pong=$(run_ssh "echo CR8818_SSH_OK" 2>/dev/null); then
        return 1
    fi
    [ "$_pong" = "CR8818_SSH_OK" ]
}

measure_icmp_rtt() {
    _phase="$1"
    if ! _pout=$(ping -c 5 -W 1 "$SSH_HOST" 2>/dev/null); then
        echo "UNAVAILABLE"
        return 0
    fi
    _loss=$(printf '%s\n' "$_pout" | sed -n 's/.*, *\([0-9.]*\)% packet loss.*/\1/p' | head -n1)
    _rtt=$(printf '%s\n' "$_pout" | awk -F'=' '/round-trip|rtt/ {print $2}' | awk '{print $1}' | head -n1)
    if [ -z "$_rtt" ]; then
        echo "UNAVAILABLE"
    else
        echo "min/avg/max=${_rtt}ms loss=${_loss:-0}%"
    fi
}

measure_throughput_hook() {
    if [ -z "$IPERF_TARGET" ]; then
        echo "HOOK_SKIPPED_NO_TARGET"
        return 0
    fi
    if ! command -v iperf3 >/dev/null 2>&1; then
        echo "UNAVAILABLE_NO_IPERF3"
        return 0
    fi
    if ! _j=$(iperf3 -c "$IPERF_TARGET" -t 5 -J 2>/dev/null); then
        echo "IPERF3_FAILED"
        return 0
    fi
    _mbps=$(printf '%s\n' "$_j" | awk '/"bits_per_second"/ {val=$2} END{gsub(/,/,"",val); if (val+0>0) printf "%.2f", val/1000000}')
    if [ -n "$_mbps" ]; then
        echo "${_mbps} Mbps"
    else
        echo "UNPARSEABLE_IPERF3"
    fi
}

collect_router_snapshot() {
    _out_file="$1"
    _cmd='
echo "RPS=$(cat ${MOCK_ROOT:-}/sys/class/net/eth0/queues/rx-0/rps_cpus 2>/dev/null | tr -d " \t\r\n" || echo UNAVAILABLE)"
_nrx=$(grep -m1 "NET_RX:" ${MOCK_ROOT:-}/proc/softirqs 2>/dev/null | awk "{print \$2, \$3}")
echo "NET_RX=${_nrx:-UNAVAILABLE}"
_ma=$(awk "/^MemAvailable:/ {print \$2}" ${MOCK_ROOT:-}/proc/meminfo 2>/dev/null)
_sl=$(awk "/^Slab:/ {print \$2}" ${MOCK_ROOT:-}/proc/meminfo 2>/dev/null)
_su=$(awk "/^SUnreclaim:/ {print \$2}" ${MOCK_ROOT:-}/proc/meminfo 2>/dev/null)
echo "MEM_AVAIL_KB=${_ma:-UNAVAILABLE}"
echo "SLAB_KB=${_sl:-UNAVAILABLE}"
echo "SUNRECLAIM_KB=${_su:-UNAVAILABLE}"
_eth_drop=$(awk -F: "\$1 ~ /^ *eth0$/ {split(\$2,a); print a[4]}" ${MOCK_ROOT:-}/proc/net/dev 2>/dev/null)
_br_drop=$(awk -F: "\$1 ~ /^ *br-lan$/ {split(\$2,a); print a[4]}" ${MOCK_ROOT:-}/proc/net/dev 2>/dev/null)
echo "ETH0_RX_DROP=${_eth_drop:-UNAVAILABLE}"
echo "BRLAN_RX_DROP=${_br_drop:-UNAVAILABLE}"
_sn0=$(sed -n "1p" ${MOCK_ROOT:-}/proc/net/softnet_stat 2>/dev/null | awk "{print \$1\":\"\$2\":\"\$3}")
_sn1=$(sed -n "2p" ${MOCK_ROOT:-}/proc/net/softnet_stat 2>/dev/null | awk "{print \$1\":\"\$2\":\"\$3}")
echo "SOFTNET_CPU0=${_sn0:-UNAVAILABLE}"
echo "SOFTNET_CPU1=${_sn1:-UNAVAILABLE}"
if [ -r "${MOCK_ROOT:-}/sys/kernel/debug/qca-nss-drv/stats/ipv4" ]; then
  _nss=$(grep -m1 -E "rx_pkts|accelerated|tx_pkts" "${MOCK_ROOT:-}/sys/kernel/debug/qca-nss-drv/stats/ipv4" 2>/dev/null | tr -s " ")
  echo "NSS_IPV4=${_nss:-PRESENT}"
else
  echo "NSS_IPV4=UNAVAILABLE"
fi
if [ -r "${MOCK_ROOT:-}/sys/kernel/debug/ecm/ecm_db/connection_count" ]; then
  _ecm=$(cat "${MOCK_ROOT:-}/sys/kernel/debug/ecm/ecm_db/connection_count" 2>/dev/null | tr -d " \t\r\n")
  echo "ECM_CONNS=${_ecm:-UNAVAILABLE}"
elif [ -d "${MOCK_ROOT:-}/sys/kernel/debug/ecm" ]; then
  echo "ECM_CONNS=DIR_PRESENT_NO_READABLE_COUNT"
else
  echo "ECM_CONNS=UNAVAILABLE"
fi
'
    run_ssh "$_cmd" > "$_out_file"
}

snap_val() {
    grep -m1 "^${1}=" "$2" 2>/dev/null | sed "s/^${1}=//" || echo "UNAVAILABLE"
}

calc_delta() {
    _a="$1"; _b="$2"
    if [ "$_a" -eq "$_a" ] 2>/dev/null && [ "$_b" -eq "$_b" ] 2>/dev/null; then
        echo $((_b - _a))
    else
        echo "UNAVAILABLE"
    fi
}

log_info "=== Phase 0: Client-Side SSH + ICMP Reachability Precondition ==="
if ! check_client_reachability; then
    log_err "Router ${SSH_HOST}:${SSH_PORT} unreachable via client ICMP/SSH. Aborting with ZERO router modifications."
    exit 1
fi
log_success "Client-side ICMP ping and pinned SSH roundtrip confirmed."

log_info "=== Phase 1: Collecting BEFORE Baseline Snapshot ==="
SNAP_BEFORE="${WORK_TMP}/snap_before.kv"
collect_router_snapshot "$SNAP_BEFORE" || { log_err "Failed to collect BEFORE snapshot"; exit 1; }
PRE_RPS=$(snap_val "RPS" "$SNAP_BEFORE")
if [ "$PRE_RPS" != "0" ] && [ "$PRE_RPS" != "00" ]; then
    log_err "Baseline rps_cpus on router is '$PRE_RPS' (expected 0). Aborting safely."
    exit 1
fi
RTT_BEFORE=$(measure_icmp_rtt "before")
TPUT_BEFORE=$(measure_throughput_hook)
log_success "Baseline snapshot recorded (rps_cpus=$PRE_RPS, NET_RX=$(snap_val NET_RX "$SNAP_BEFORE"), RTT=$RTT_BEFORE)."

log_info "=== Phase 2: Staging Volatile Trial Runner via Stdin Pipe (/tmp only) ==="
# shellcheck disable=SC2086
ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "mkdir -p \$(dirname \${MOCK_ROOT:-}${REMOTE_RUNNER}) && cat > \${MOCK_ROOT:-}${REMOTE_RUNNER} && chmod +x \${MOCK_ROOT:-}${REMOTE_RUNNER}" < "$RUNNER_LOCAL" \
    || { log_err "Failed to stage $REMOTE_RUNNER to router /tmp"; exit 1; }

# Start background continuous client reachability monitor
MON_FAIL_FLAG="${WORK_TMP}/client_lost_reachability"
(
    _consec=0
    while true; do
        sleep "$MONITOR_INTERVAL" </dev/null
        if ! check_client_reachability; then
            _consec=$((_consec + 1))
            if [ "$_consec" -ge 2 ]; then
                echo "LOST_REACHABILITY" > "$MON_FAIL_FLAG"
                log_err "CRITICAL: Client lost reachability during active trial! Attempting out-of-band restore..."
                run_ssh "printf '0\n' > \${MOCK_ROOT:-}${TARGET_SYSFS}" >/dev/null 2>&1 || true
                break
            fi
        else
            _consec=0
        fi
    done
) </dev/null &
MON_PID=$!

log_info "=== Phase 3: Executing Controlled Single-Variable RPS Trial (${MEASURE_SECONDS}s) ==="
RUNNER_LOG="${WORK_TMP}/runner_remote.log"
run_ssh "CLIENT_REACHABILITY_VERIFIED=1 REQUIRE_ENDPOINT_PROBE=1 REQUIRE_SOFTIRQ_TELEMETRY=1 MEASURE_SECONDS=${MEASURE_SECONDS} WATCHDOG_TIMEOUT=${WATCHDOG_TIMEOUT} sh \${MOCK_ROOT:-}${REMOTE_RUNNER} run" \
    > "$RUNNER_LOG" 2>&1 &
RUNNER_PID=$!

# Capture DURING telemetry once trial enters RPS=2 state
SNAP_DURING="${WORK_TMP}/snap_during.kv"
DURING_CAPTURED=0
_wait_s=0
while kill -0 "$RUNNER_PID" 2>/dev/null; do
    if [ -f "$MON_FAIL_FLAG" ]; then
        log_err "Client reachability monitor triggered abort!"
        kill "$RUNNER_PID" 2>/dev/null || true
        break
    fi
    if [ "$DURING_CAPTURED" -eq 0 ] && [ "$_wait_s" -ge 1 ]; then
        if collect_router_snapshot "$SNAP_DURING" 2>/dev/null; then
            if [ "$(snap_val RPS "$SNAP_DURING")" = "2" ]; then
                DURING_CAPTURED=1
                RTT_DURING=$(measure_icmp_rtt "during")
                TPUT_DURING=$(measure_throughput_hook)
                log_info "During-trial telemetry captured (rps_cpus=2, NET_RX=$(snap_val NET_RX "$SNAP_DURING"))."
            fi
        fi
    fi
    sleep 1
    _wait_s=$((_wait_s + 1))
done

wait "$RUNNER_PID"
RUNNER_RC=$?
RUNNER_PID=""

if [ -n "${MON_PID:-}" ]; then
    kill "$MON_PID" 2>/dev/null || true
    wait "$MON_PID" 2>/dev/null || true
    MON_PID=""
fi

if [ "$DURING_CAPTURED" -eq 0 ]; then
    RTT_DURING="NOT_CAPTURED"
    TPUT_DURING="NOT_CAPTURED"
fi

log_info "=== Phase 4: Independent Post-Trial Verification & Cleanup ==="
SNAP_AFTER="${WORK_TMP}/snap_after.kv"
collect_router_snapshot "$SNAP_AFTER" || { log_err "Failed to collect AFTER snapshot"; exit 1; }
POST_RPS=$(snap_val "RPS" "$SNAP_AFTER")
STATE_PRESENT=$(run_ssh "[ -f \${MOCK_ROOT:-}/tmp/trial_state/rps_trial.state ] && echo PRESENT || echo CLEAN" 2>/dev/null || echo "UNKNOWN")
run_ssh "rm -f \${MOCK_ROOT:-}${REMOTE_RUNNER}" >/dev/null 2>&1 || true

RTT_AFTER=$(measure_icmp_rtt "after")
TPUT_AFTER=$(measure_throughput_hook)

B_RX0=$(snap_val "NET_RX" "$SNAP_BEFORE" | awk '{print $1}')
B_RX1=$(snap_val "NET_RX" "$SNAP_BEFORE" | awk '{print $2}')
A_RX0=$(snap_val "NET_RX" "$SNAP_AFTER" | awk '{print $1}')
A_RX1=$(snap_val "NET_RX" "$SNAP_AFTER" | awk '{print $2}')
D_RX0=$(calc_delta "$B_RX0" "$A_RX0")
D_RX1=$(calc_delta "$B_RX1" "$A_RX1")

cat << EOF > "$REPORT_TXT"
================================================================================
CONTROLLED RPS eth0/rx-0 TRIAL REPORT (${TS_TAG})
================================================================================
Target:                   ${SSH_USER}@${SSH_HOST}:${SSH_PORT} (${TARGET_SYSFS})
Runner Exit Code:         ${RUNNER_RC}
Client Monitor Lost Conn: $([ -f "$MON_FAIL_FLAG" ] && echo YES || echo NO)
Verified Post rps_cpus:   ${POST_RPS} (State File: ${STATE_PRESENT})

--- BEFORE / DURING / AFTER TELEMETRY ---
NET_RX [CPU0 CPU1] Before: $(snap_val NET_RX "$SNAP_BEFORE")
NET_RX [CPU0 CPU1] During: $([ "$DURING_CAPTURED" -eq 1 ] && snap_val NET_RX "$SNAP_DURING" || echo NOT_CAPTURED)
NET_RX [CPU0 CPU1] After:  $(snap_val NET_RX "$SNAP_AFTER")
NET_RX Delta (CPU0 / CPU1): +${D_RX0} / +${D_RX1}
ICMP RTT Before:          ${RTT_BEFORE}
ICMP RTT During:          ${RTT_DURING}
ICMP RTT After:           ${RTT_AFTER}
Throughput Before:        ${TPUT_BEFORE}
Throughput During:        ${TPUT_DURING}
Throughput After:         ${TPUT_AFTER}
eth0 RX drops (B -> A):   $(snap_val ETH0_RX_DROP "$SNAP_BEFORE") -> $(snap_val ETH0_RX_DROP "$SNAP_AFTER")
br-lan RX drops (B -> A): $(snap_val BRLAN_RX_DROP "$SNAP_BEFORE") -> $(snap_val BRLAN_RX_DROP "$SNAP_AFTER")
softnet CPU0 (B -> A):    $(snap_val SOFTNET_CPU0 "$SNAP_BEFORE") -> $(snap_val SOFTNET_CPU0 "$SNAP_AFTER")
softnet CPU1 (B -> A):    $(snap_val SOFTNET_CPU1 "$SNAP_BEFORE") -> $(snap_val SOFTNET_CPU1 "$SNAP_AFTER")
NSS IPv4 (B -> A):        $(snap_val NSS_IPV4 "$SNAP_BEFORE") -> $(snap_val NSS_IPV4 "$SNAP_AFTER")
ECM Conns (B -> A):       $(snap_val ECM_CONNS "$SNAP_BEFORE") -> $(snap_val ECM_CONNS "$SNAP_AFTER")
MemAvailable KB (B -> A): $(snap_val MEM_AVAIL_KB "$SNAP_BEFORE") -> $(snap_val MEM_AVAIL_KB "$SNAP_AFTER")
Slab / SUnreclaim (B->A): $(snap_val SLAB_KB "$SNAP_BEFORE")/$(snap_val SUNRECLAIM_KB "$SNAP_BEFORE") -> $(snap_val SLAB_KB "$SNAP_AFTER")/$(snap_val SUNRECLAIM_KB "$SNAP_AFTER")

[INTERPRETATION CAVEAT]
Shifting NET_RX softirqs onto CPU1 confirms IRQ steering only. It does NOT
prove increased WAN/LAN throughput or reduced latency unless throughput/RTT
measurements explicitly improve under active load.

Manual Recovery Command:
  ${MANUAL_RECOVERY_CMD}
================================================================================
EOF

cat << EOF > "$REPORT_JSON"
{
  "trial": "eth0_rx0_rps",
  "timestamp": "${TS_TAG}",
  "runner_exit_code": ${RUNNER_RC},
  "client_reachability_lost": $([ -f "$MON_FAIL_FLAG" ] && echo true || echo false),
  "post_rps_cpus": "${POST_RPS}",
  "post_state_file": "${STATE_PRESENT}",
  "net_rx_delta_cpu0": "${D_RX0}",
  "net_rx_delta_cpu1": "${D_RX1}",
  "rtt_before": "${RTT_BEFORE}",
  "rtt_during": "${RTT_DURING}",
  "rtt_after": "${RTT_AFTER}",
  "throughput_before": "${TPUT_BEFORE}",
  "throughput_during": "${TPUT_DURING}",
  "throughput_after": "${TPUT_AFTER}"
}
EOF

cat "$REPORT_TXT"
log_info "Saved TXT report:  $REPORT_TXT"
log_info "Saved JSON report: $REPORT_JSON"

if [ -f "$MON_FAIL_FLAG" ] || [ "$RUNNER_RC" -ne 0 ] || [ "$POST_RPS" != "0" -a "$POST_RPS" != "00" ] || [ "$STATE_PRESENT" != "CLEAN" ]; then
    log_err "Trial verification failed or aborted abnormally! Inspect $RUNNER_LOG and $REPORT_TXT."
    exit 1
fi

log_success "Controlled RPS trial orchestrated, verified restored (rps_cpus=${POST_RPS}), and reported cleanly."
exit 0
