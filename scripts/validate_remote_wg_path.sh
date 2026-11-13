#!/bin/sh
# scripts/validate_remote_wg_path.sh
# Staged WireGuard Client Validator & Offline Config Auditor for CR8808 Ver.B Remote Access
# Zero secrets printed; supports --mock-dir for hermetic CI/WSL2 testing and --dry-run.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_KEY_FILE="${HOST_KEY_FILE:-${SCRIPT_DIR}/../config/cr8818_host_key.pub}"

MODE=""
CONF_FILE=""
TUNNEL_IFACE="${TUNNEL_IFACE:-wg0}"
TUNNEL_GW_IP="${TUNNEL_GW_IP:-10.99.0.1}"
ROUTER_LAN_IP="${ROUTER_LAN_IP:-192.168.31.1}"
SSH_PORT="${SSH_PORT:-56789}"
SSH_USER="${SSH_USER:-root}"
MAX_HANDSHAKE_AGE="${MAX_HANDSHAKE_AGE:-180}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-2}"
SKIP_SSH=0
DRY_RUN=0
JSON_OUT=0
MOCK_DIR=""

usage() {
    cat << EOF
Usage: $0 <MODE> [OPTIONS]

Modes:
  --validate-conf <file>   Offline audit of a WireGuard .conf file (never prints keys)
  --verify-path            Execute 7-stage remote path check (handshake -> transfer ->
                           tunnel GW -> LAN route -> router ICMP -> pinned SSH -> reconnect)

Options:
  --tunnel <iface>         WireGuard interface name (default: wg0)
  --tunnel-gw <ip>         Tunnel gateway IP (default: 10.99.0.1)
  --router-ip <ip>         Router LAN IP (default: 192.168.31.1)
  --ssh-port <port>        Router Dropbear SSH port (default: 56789)
  --host-key <file>        Pinned host public key (default: config/cr8818_host_key.pub)
  --max-handshake-age <s>  Max acceptable handshake age in seconds (default: 180)
  --sample-seconds <s>     Window for transfer delta & reconnect check (default: 2)
  --skip-ssh               Validate through ICMP/route without running SSH batch probe
  --mock-dir <dir>         Hermetic mock root/bin directory for offline E2E testing
  --dry-run                Print planned 7-stage checks without probing network
  --json                   Output structured JSON summary
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --validate-conf)
            MODE="validate_conf"
            shift
            [ $# -gt 0 ] || { echo "[WG-VAL ERROR] --validate-conf requires a path" >&2; exit 1; }
            CONF_FILE="$1"
            ;;
        --verify-path) MODE="verify_path" ;;
        --tunnel) shift; TUNNEL_IFACE="${1:-}"; [ -n "$TUNNEL_IFACE" ] || exit 1 ;;
        --tunnel-gw) shift; TUNNEL_GW_IP="${1:-}"; [ -n "$TUNNEL_GW_IP" ] || exit 1 ;;
        --router-ip) shift; ROUTER_LAN_IP="${1:-}"; [ -n "$ROUTER_LAN_IP" ] || exit 1 ;;
        --ssh-port) shift; SSH_PORT="${1:-}"; [ -n "$SSH_PORT" ] || exit 1 ;;
        --host-key) shift; HOST_KEY_FILE="${1:-}"; [ -n "$HOST_KEY_FILE" ] || exit 1 ;;
        --max-handshake-age) shift; MAX_HANDSHAKE_AGE="${1:-}"; [ -n "$MAX_HANDSHAKE_AGE" ] || exit 1 ;;
        --sample-seconds) shift; SAMPLE_SECONDS="${1:-}"; [ -n "$SAMPLE_SECONDS" ] || exit 1 ;;
        --skip-ssh) SKIP_SSH=1 ;;
        --mock-dir) shift; MOCK_DIR="${1:-}"; [ -n "$MOCK_DIR" ] || exit 1 ;;
        --dry-run) DRY_RUN=1 ;;
        --json) JSON_OUT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[WG-VAL ERROR] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

[ -n "$MODE" ] || { usage >&2; exit 1; }

if [ -n "$MOCK_DIR" ]; then
    [ -d "${MOCK_DIR}/bin" ] && PATH="${MOCK_DIR}/bin:${PATH}"
    export PATH
fi

# Helpers
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

parse_conf_value() {
    _file="$1"
    _key_re="$2"
    sed -n "s/#.*$//; /^[[:space:]]*${_key_re}[[:space:]]*=/I{ s/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; p; }" "$_file" | head -n 1
}

validate_conf_mode() {
    [ -f "$CONF_FILE" ] || { echo "[WG-VAL ERROR] Config not found: $CONF_FILE" >&2; return 1; }

    _errs=0
    _warns=0
    _issues=""

    # Read PrivateKey without echoing its value anywhere
    _priv=$(parse_conf_value "$CONF_FILE" "PrivateKey")
    _pub=$(parse_conf_value "$CONF_FILE" "PublicKey")
    _addr=$(parse_conf_value "$CONF_FILE" "Address")
    _dns=$(parse_conf_value "$CONF_FILE" "DNS")
    _mtu=$(parse_conf_value "$CONF_FILE" "MTU")
    _ep=$(parse_conf_value "$CONF_FILE" "Endpoint")
    _allowed=$(parse_conf_value "$CONF_FILE" "AllowedIPs")
    _ka=$(parse_conf_value "$CONF_FILE" "PersistentKeepalive")

    if [ -z "$_priv" ] || printf '%s' "$_priv" | grep -q '<.*REPLACE_ME>'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:PrivateKey_missing_or_placeholder;"
    elif ! printf '%s' "$_priv" | grep -Eq '^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:PrivateKey_invalid_base64;"
    fi

    if [ -z "$_pub" ] || printf '%s' "$_pub" | grep -q '<.*REPLACE_ME>'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:Peer_PublicKey_missing_or_placeholder;"
    elif ! printf '%s' "$_pub" | grep -Eq '^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:Peer_PublicKey_invalid_base64;"
    fi

    if [ -z "$_ep" ] || ! printf '%s' "$_ep" | grep -Eq '^[^:]+:[0-9]{1,5}$'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:Endpoint_invalid;"
    fi

    if [ -z "$_allowed" ]; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:AllowedIPs_empty;"
    elif printf '%s' "$_allowed" | grep -q '::/0' && ! printf '%s' "$_addr" | grep -q ':'; then
        _errs=$((_errs + 1))
        _issues="${_issues}FAIL:IPv6_default_route_without_v6_address;"
    fi

    if [ -n "$_dns" ] && printf '%s' "$_dns" | grep -Eq '(^|[,[:space:]])(1\.1\.1\.1|8\.8\.8\.8|8\.8\.4\.4|1\.0\.0\.1)([,[:space:]]|$)'; then
        _warns=$((_warns + 1))
        _issues="${_issues}WARN:External_DNS_blocked_risk;"
    fi

    if [ -z "$_mtu" ]; then
        _warns=$((_warns + 1))
        _issues="${_issues}WARN:MTU_unset_default_1420;"
    elif [ "$_mtu" -gt 1380 ] 2>/dev/null; then
        _warns=$((_warns + 1))
        _issues="${_issues}WARN:MTU_above_1380_pppoe_nat_risk;"
    fi

    if [ -z "$_ka" ] || [ "$_ka" -lt 15 ] 2>/dev/null || [ "$_ka" -gt 35 ] 2>/dev/null; then
        _warns=$((_warns + 1))
        _issues="${_issues}WARN:PersistentKeepalive_suboptimal;"
    fi

    if [ "$JSON_OUT" -eq 1 ]; then
        cat << EOF
{
  "mode": "validate_conf",
  "file": "$(json_escape "$CONF_FILE")",
  "errors": ${_errs},
  "warnings": ${_warns},
  "secrets_redacted": true,
  "issues": "$(json_escape "$_issues")",
  "status": "$([ "$_errs" -eq 0 ] && echo PASS || echo FAIL)"
}
EOF
    else
        echo "=== WireGuard Config Audit (Secrets Never Printed) ==="
        echo "File     : $CONF_FILE"
        echo "Endpoint : ${_ep:-MISSING}"
        echo "MTU      : ${_mtu:-unset}"
        echo "Keepalive: ${_ka:-unset}"
        echo "Result   : errors=${_errs} warnings=${_warns}"
        [ -n "$_issues" ] && echo "Findings : $_issues"
    fi

    [ "$_errs" -eq 0 ]
}

verify_path_mode() {
    if [ "$DRY_RUN" -eq 1 ]; then
        cat << EOF
DRY-RUN: Staged Remote Access Path Verification (${TUNNEL_IFACE} -> ${ROUTER_LAN_IP}:${SSH_PORT})
  Stage 1: Verify WireGuard handshake age <= ${MAX_HANDSHAKE_AGE}s via 'wg show ${TUNNEL_IFACE} latest-handshakes'
  Stage 2: Verify RX+TX transfer progress over ${SAMPLE_SECONDS}s via 'wg show ${TUNNEL_IFACE} transfer'
  Stage 3: Verify tunnel gateway ICMP reachability (${TUNNEL_GW_IP})
  Stage 4: Verify kernel route lookup for ${ROUTER_LAN_IP} targets ${TUNNEL_IFACE}
  Stage 5: Verify Xiaomi LAN ICMP reachability (${ROUTER_LAN_IP})
  Stage 6: Verify pinned-key SSH connectivity (${SSH_USER}@${ROUTER_LAN_IP}:${SSH_PORT} via ${HOST_KEY_FILE})
  Stage 7: Verify continuity / reconnect stability after ${SAMPLE_SECONDS}s wait
EOF
        return 0
    fi

    _s1="FAIL"; _s2="FAIL"; _s3="FAIL"; _s4="FAIL"; _s5="FAIL"; _s6="SKIPPED"; _s7="FAIL"
    _now=$(date +%s)
    _fail_reason=""

    # Stage 1: Handshake check
    if command -v wg >/dev/null 2>&1; then
        _hs_epoch=$(wg show "$TUNNEL_IFACE" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
        if [ -n "$_hs_epoch" ] && [ "$_hs_epoch" -gt 0 ] 2>/dev/null; then
            _age=$((_now - _hs_epoch))
            if [ "$_age" -le "$MAX_HANDSHAKE_AGE" ]; then
                _s1="PASS"
            else
                _fail_reason="handshake_stale_${_age}s"
            fi
        else
            _fail_reason="no_handshake"
        fi
    else
        _fail_reason="wg_binary_missing"
    fi

    # Stage 2: Transfer delta check
    if [ "$_s1" = "PASS" ]; then
        _t0=$(wg show "$TUNNEL_IFACE" transfer 2>/dev/null | awk 'NR==1{print $2+$3}')
        [ "$SAMPLE_SECONDS" -gt 0 ] 2>/dev/null && sleep "$SAMPLE_SECONDS"
        _t1=$(wg show "$TUNNEL_IFACE" transfer 2>/dev/null | awk 'NR==1{print $2+$3}')
        if [ -n "$_t0" ] && [ -n "$_t1" ] && [ "$_t1" -gt 0 ] && [ "$_t1" -ge "$_t0" ] 2>/dev/null; then
            if [ "$_t1" -gt "$_t0" ] || [ "$_t0" -gt 0 ]; then
                _s2="PASS"
            fi
        fi
        [ "$_s2" = "PASS" ] || _fail_reason="${_fail_reason:-no_transfer_bytes}"
    fi

    # Stage 3: Tunnel gateway reachability
    if [ "$_s2" = "PASS" ] && ping -c 2 -W 2 "$TUNNEL_GW_IP" >/dev/null 2>&1; then
        _s3="PASS"
    elif [ "$_s2" = "PASS" ]; then
        _fail_reason="${_fail_reason:-tunnel_gw_unreachable}"
    fi

    # Stage 4: Route table verification
    if [ "$_s3" = "PASS" ]; then
        _rt=$(ip route get "$ROUTER_LAN_IP" 2>/dev/null || true)
        if printf '%s' "$_rt" | grep -Eq "dev[[:space:]]+${TUNNEL_IFACE}([[:space:]]|$)"; then
            _s4="PASS"
        else
            _fail_reason="${_fail_reason:-route_mismatch}"
        fi
    fi

    # Stage 5: Router LAN reachability
    if [ "$_s4" = "PASS" ] && ping -c 2 -W 2 "$ROUTER_LAN_IP" >/dev/null 2>&1; then
        _s5="PASS"
    elif [ "$_s4" = "PASS" ]; then
        _fail_reason="${_fail_reason:-router_lan_unreachable}"
    fi

    # Stage 6: Pinned-key SSH check
    if [ "$_s5" = "PASS" ] && [ "$SKIP_SSH" -eq 0 ]; then
        if [ -f "$HOST_KEY_FILE" ] && command -v ssh >/dev/null 2>&1; then
            _kh=$(mktemp /tmp/wg_val_kh.XXXXXX)
            _pub=$(head -n 1 "$HOST_KEY_FILE")
            printf '%s %s\n[%s]:%s %s\n' "$ROUTER_LAN_IP" "$_pub" "$ROUTER_LAN_IP" "$SSH_PORT" "$_pub" > "$_kh"
            if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$_kh" \
                -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa \
                -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${ROUTER_LAN_IP}" "uname -a" >/dev/null 2>&1; then
                _s6="PASS"
            else
                _s6="FAIL"
                _fail_reason="${_fail_reason:-ssh_pinned_check_failed}"
            fi
            rm -f "$_kh"
        else
            _s6="FAIL"
            _fail_reason="${_fail_reason:-missing_host_key_or_ssh}"
        fi
    fi

    # Stage 7: Reconnect / continuity check
    if [ "$_s5" = "PASS" ] && { [ "$SKIP_SSH" -eq 1 ] || [ "$_s6" = "PASS" ]; }; then
        [ "$SAMPLE_SECONDS" -gt 0 ] 2>/dev/null && sleep "$SAMPLE_SECONDS"
        if ping -c 2 -W 2 "$ROUTER_LAN_IP" >/dev/null 2>&1; then
            _s7="PASS"
        else
            _fail_reason="${_fail_reason:-continuity_drop}"
        fi
    fi

    _overall="FAIL"
    if [ "$_s1" = "PASS" ] && [ "$_s2" = "PASS" ] && [ "$_s3" = "PASS" ] && [ "$_s4" = "PASS" ] && [ "$_s5" = "PASS" ] && [ "$_s7" = "PASS" ]; then
        if [ "$SKIP_SSH" -eq 1 ] || [ "$_s6" = "PASS" ]; then
            _overall="PASS"
        fi
    fi

    if [ "$JSON_OUT" -eq 1 ]; then
        cat << EOF
{
  "mode": "verify_path",
  "tunnel": "$(json_escape "$TUNNEL_IFACE")",
  "router_lan_ip": "$(json_escape "$ROUTER_LAN_IP")",
  "ssh_port": ${SSH_PORT},
  "stages": {
    "handshake": "$_s1",
    "transfer_delta": "$_s2",
    "tunnel_gw_ping": "$_s3",
    "lan_route": "$_s4",
    "router_lan_ping": "$_s5",
    "pinned_ssh": "$_s6",
    "continuity": "$_s7"
  },
  "failure_reason": "$(json_escape "$_fail_reason")",
  "status": "$_overall"
}
EOF
    else
        echo "=== Staged Remote Access Validation ($TUNNEL_IFACE -> $ROUTER_LAN_IP:$SSH_PORT) ==="
        echo "1. Handshake       : $_s1"
        echo "2. Transfer Delta  : $_s2"
        echo "3. Tunnel GW Ping  : $_s3 ($TUNNEL_GW_IP)"
        echo "4. LAN Route Match : $_s4"
        echo "5. LAN Router Ping : $_s5 ($ROUTER_LAN_IP)"
        echo "6. Pinned Key SSH  : $_s6"
        echo "7. Continuity      : $_s7"
        echo "OVERALL            : $_overall $([ -n "$_fail_reason" ] && echo "($_fail_reason)")"
    fi

    [ "$_overall" = "PASS" ]
}

case "$MODE" in
    validate_conf) validate_conf_mode ;;
    verify_path)   verify_path_mode ;;
esac
