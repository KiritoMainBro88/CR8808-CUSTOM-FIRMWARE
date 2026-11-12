#!/bin/sh
# scripts/firewall_manager.sh
# Production Helper for M11.1 Netfilter Firewall Rule Operations
# Supports explicit ownership tagging, duplicate apply prevention,
# position-1 verification, idempotent rollback, and atomic rollback on partial failure.
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

IPTABLES_CMD="${IPTABLES_CMD:-iptables}"
IP6TABLES_CMD="${IP6TABLES_CMD:-ip6tables}"

check_chains() {
    if ! $IPTABLES_CMD -L "$CHAIN_V4" -n >/dev/null 2>&1; then
        echo "[ERROR] IPv4 chain '$CHAIN_V4' does not exist or is inaccessible." >&2
        return 1
    fi
    if ! $IP6TABLES_CMD -L "$CHAIN_V6" -n >/dev/null 2>&1; then
        echo "[ERROR] IPv6 chain '$CHAIN_V6' does not exist or is inaccessible." >&2
        return 1
    fi
    return 0
}

check_position_internal() {
    FAMILY="$1"
    CHAIN="$2"
    TARGET_TAG="$3"
    EXPECTED_POS="$4"
    
    if [ "$FAMILY" = "ipv4" ] || [ "$FAMILY" = "v4" ]; then
        CMD="$IPTABLES_CMD"
    elif [ "$FAMILY" = "ipv6" ] || [ "$FAMILY" = "v6" ]; then
        CMD="$IP6TABLES_CMD"
    else
        echo "[ERROR] Unknown protocol family '$FAMILY'. Expected 'ipv4'/'v4' or 'ipv6'/'v6'." >&2
        return 1
    fi
    
    FIRST_RULE=$($CMD -S "$CHAIN" "$EXPECTED_POS" 2>/dev/null || true)
    if echo "$FIRST_RULE" | grep -Fq -- "$TARGET_TAG"; then
        return 0
    else
        echo "[ERROR] Rule with tag '$TARGET_TAG' is NOT at position $EXPECTED_POS in $FAMILY chain $CHAIN." >&2
        echo "        Actual rule at position $EXPECTED_POS: $FIRST_RULE" >&2
        return 1
    fi
}

# Returns:
#   0 = Rule with TARGET_TAG exists in CHAIN
#   1 = Rule does NOT exist in CHAIN (command succeeded, tag not found)
#   2 = Execution error or CHAIN inaccessible
rule_exists() {
    FAMILY="$1"
    CHAIN="$2"
    TARGET_TAG="$3"
    
    if [ "$FAMILY" = "ipv4" ] || [ "$FAMILY" = "v4" ]; then
        CMD="$IPTABLES_CMD"
    elif [ "$FAMILY" = "ipv6" ] || [ "$FAMILY" = "v6" ]; then
        CMD="$IP6TABLES_CMD"
    else
        echo "[ERROR] Unknown protocol family '$FAMILY'." >&2
        return 2
    fi
    
    RULES=$($CMD -S "$CHAIN" 2>/dev/null)
    CMD_RET=$?
    if [ "$CMD_RET" -ne 0 ]; then
        echo "[ERROR] Failed to query $FAMILY chain '$CHAIN' (exit $CMD_RET)." >&2
        return 2
    fi
    
    if echo "$RULES" | grep -Fq -- "$TARGET_TAG"; then
        return 0
    else
        return 1
    fi
}

do_apply() {
    check_chains || return 1
    
    # 1. Prevent duplicate apply: Check if rule with same tag already exists
    rule_exists "ipv4" "$CHAIN_V4" "$TAG"
    STATUS_V4=$?
    rule_exists "ipv6" "$CHAIN_V6" "$TAG"
    STATUS_V6=$?
    
    if [ "$STATUS_V4" -eq 2 ] || [ "$STATUS_V6" -eq 2 ]; then
        echo "[ERROR] Pre-apply check failed: cannot query rule tables." >&2
        return 1
    fi
    if [ "$STATUS_V4" -eq 0 ] || [ "$STATUS_V6" -eq 0 ]; then
        echo "[ERROR] Trial rule with tag '$TAG' already exists in chain. Duplicate apply rejected." >&2
        return 1
    fi
    
    echo "[FIREWALL] Inserting IPv4 trial rule at position 1 with tag '$TAG'..."
    if ! $IPTABLES_CMD -I "$CHAIN_V4" 1 -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP; then
        echo "[ERROR] Failed to insert IPv4 trial rule." >&2
        return 1
    fi
    
    echo "[FIREWALL] Inserting IPv6 trial rule at position 1 with tag '$TAG'..."
    if ! $IP6TABLES_CMD -I "$CHAIN_V6" 1 -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP; then
        echo "[ERROR] Failed to insert IPv6 trial rule! Initiating atomic rollback of IPv4..." >&2
        
        # Atomic rollback of IPv4 rule
        while $IPTABLES_CMD -D "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; do
            :
        done
        
        # Verify IPv4 rule actually disappeared
        rule_exists "ipv4" "$CHAIN_V4" "$TAG"
        VERIFY_V4=$?
        if [ "$VERIFY_V4" -ne 1 ]; then
            echo "[CRITICAL ERROR] ROLLBACK_FAILED: IPv4 rule could NOT be eliminated after IPv6 insertion failure!" >&2
            return 2
        fi
        
        echo "[FIREWALL] Atomic rollback succeeded: IPv4 trial rule removed and verified." >&2
        return 1
    fi
    
    # 2. Strict Position-1 Verification
    if ! check_position_internal "ipv4" "$CHAIN_V4" "$TAG" 1 || ! check_position_internal "ipv6" "$CHAIN_V6" "$TAG" 1; then
        echo "[ERROR] Position verification failed after insertion! Rolling back..." >&2
        do_rollback
        return 1
    fi
    
    echo "[FIREWALL] Dual-stack trial rules applied and confirmed at position 1."
    return 0
}

do_rollback() {
    # Check chain existence and accessibility
    if ! check_chains; then
        echo "[CRITICAL ERROR] Cannot execute rollback: one or more chains do not exist or are inaccessible!" >&2
        return 2
    fi
    
    echo "[FIREWALL] Rolling back IPv4 rules matching tag '$TAG'..."
    while $IPTABLES_CMD -D "$CHAIN_V4" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; do
        :
    done
    
    echo "[FIREWALL] Rolling back IPv6 rules matching tag '$TAG'..."
    while $IP6TABLES_CMD -D "$CHAIN_V6" -p tcp --dport "$PORT" -m comment --comment "$TAG" -j DROP 2>/dev/null; do
        :
    done
    
    # Verify zero residual rules matching $TAG remain in either chain
    rule_exists "ipv4" "$CHAIN_V4" "$TAG"
    RES_V4=$?
    rule_exists "ipv6" "$CHAIN_V6" "$TAG"
    RES_V6=$?
    
    if [ "$RES_V4" -eq 2 ] || [ "$RES_V6" -eq 2 ]; then
        echo "[CRITICAL ERROR] Cannot verify rollback: query failed for one or more chains!" >&2
        return 2
    fi
    if [ "$RES_V4" -ne 1 ] || [ "$RES_V6" -ne 1 ]; then
        echo "[CRITICAL ERROR] Rollback verification failed! Residual rules matching tag '$TAG' still remain in chains!" >&2
        return 1
    fi
    
    echo "[FIREWALL] Idempotent targeted rollback completed and verified."
    return 0
}

do_verify() {
    check_position_internal "ipv4" "$CHAIN_V4" "$TAG" 1 && check_position_internal "ipv6" "$CHAIN_V6" "$TAG" 1
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
        # Standardized syntax: check_position <FAMILY> <CHAIN> <TAG> <EXPECTED_POS>
        FAMILY="${2:-ipv4}"
        CHAIN="${3:-zone_wan_input}"
        TARGET_TAG="${4:-M11_1_TRIAL_SSH_BLOCK}"
        EXPECTED_POS="${5:-1}"
        check_position_internal "$FAMILY" "$CHAIN" "$TARGET_TAG" "$EXPECTED_POS"
        ;;
    *)
        echo "Usage: $0 {apply|rollback|verify|check_position} ..." >&2
        exit 1
        ;;
esac
