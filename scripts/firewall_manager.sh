#!/bin/sh
# scripts/firewall_manager.sh
# Production Helper for M11.1 Netfilter Firewall Rule Operations
# Supports explicit ownership tagging, pre-flight checks, position-1 verification,
# and transactional atomic rollback on partial failure.
#
# Usage:
#   sh scripts/firewall_manager.sh apply <CHAIN_V4> <CHAIN_V6> <PORT> <TAG>
#   sh scripts/firewall_manager.sh rollback <CHAIN_V4> <CHAIN_V6> <PORT> <TAG>
#   sh scripts/firewall_manager.sh verify <CHAIN_V4> <CHAIN_V6> <PORT> <TAG>
#   sh scripts/firewall_manager.sh check_position <FAMILY> <CHAIN> <TAG> <EXPECTED_POS>

ACTION="${1:-verify}"
CHAIN_V4="${2:-zone_wan_input}"
CHAIN_V6="${3:-zone_wan_input}"
PORT="${4:-56789}"
TAG="${5:-M11_1_TRIAL_SSH_BLOCK}"

# Check for required iptables / ip6tables binaries or mock wrappers
IPTABLES_CMD="${IPTABLES_CMD:-iptables}"
IP6TABLES_CMD="${IP6TABLES_CMD:-ip6tables}"

check_chains() {
    if ! $IPTABLES_CMD -L "$CHAIN_V4" -n >/dev/null 2>&1; then
        echo "[ERROR] IPv4 chain $CHAIN_V4 does not exist." >&2
        return 1
    fi
    if ! $IP6TABLES_CMD -L "$CHAIN_V6" -n >/dev/null 2>&1; then
        echo "[ERROR] IPv6 chain $CHAIN_V6 does not exist." >&2
        return 1
    fi
    return 0
}

check_position_internal() {
    FAMILY="$1"
    CHAIN="$2"
    EXPECTED_POS="$3"
    
    if [ "$FAMILY" = "ipv4" ]; then
        CMD="$IPTABLES_CMD"
    else
        CMD="$IP6TABLES_CMD"
    fi
    
    FIRST_RULE=$($CMD -S "$CHAIN" "$EXPECTED_POS" 2>/dev/null || true)
    if echo "$FIRST_RULE" | grep -Fq -- "$TAG"; then
        return 0
    else
        echo "[ERROR] Rule with tag '$TAG' is NOT at position $EXPECTED_POS in $FAMILY chain $CHAIN." >&2
        echo "        Actual rule at position $EXPECTED_POS: $FIRST_RULE" >&2
        return 1
    fi
}

do_apply() {
    check_chains || return 1
    
    echo "[FIREWALL] Inserting IPv4 trial rule at position 1 with tag '$TAG'..."
    if ! $IPTABLES_CMD -I "$CHAIN_V4" 1 -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP; then
        echo "[ERROR] Failed to insert IPv4 trial rule." >&2
        return 1
    fi
    
    echo "[FIREWALL] Inserting IPv6 trial rule at position 1 with tag '$TAG'..."
    if ! $IP6TABLES_CMD -I "$CHAIN_V6" 1 -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP; then
        echo "[ERROR] Failed to insert IPv6 trial rule! Initiating atomic rollback of IPv4..." >&2
        $IPTABLES_CMD -D "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null || true
        return 1
    fi
    
    # Verify both rules are active and at position 1
    check_position_internal "ipv4" "$CHAIN_V4" 1 || { do_rollback; return 1; }
    check_position_internal "ipv6" "$CHAIN_V6" 1 || { do_rollback; return 1; }
    
    echo "[FIREWALL] Dual-stack trial rules applied and confirmed at position 1."
    return 0
}

do_rollback() {
    STATUS_V4=0
    STATUS_V6=0
    
    echo "[FIREWALL] Rolling back IPv4 rule matching tag '$TAG'..."
    if ! $IPTABLES_CMD -D "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
        STATUS_V4=1
    fi
    
    echo "[FIREWALL] Rolling back IPv6 rule matching tag '$TAG'..."
    if ! $IP6TABLES_CMD -D "$CHAIN_V6" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; then
        STATUS_V6=1
    fi
    
    if [ "$STATUS_V4" -ne 0 ] || [ "$STATUS_V6" -ne 0 ]; then
        echo "[WARN] One or more rollback deletions returned non-zero (rules may already be removed)." >&2
        return 1
    fi
    
    echo "[FIREWALL] Targeted rollback completed cleanly."
    return 0
}

do_verify() {
    check_position_internal "ipv4" "$CHAIN_V4" 1 && check_position_internal "ipv6" "$CHAIN_V6" 1
}

case "$ACTION" in
    apply)
        do_apply
        ;;
    rollback)
        do_rollback
        ;;
    verify)
        do_verify
        ;;
    check_position)
        FAMILY="${2:-ipv4}"
        CHAIN="${3:-zone_wan_input}"
        POS="${4:-1}"
        check_position_internal "$FAMILY" "$CHAIN" "$POS"
        ;;
    *)
        echo "Usage: $0 {apply|rollback|verify|check_position} ..." >&2
        exit 1
        ;;
esac
