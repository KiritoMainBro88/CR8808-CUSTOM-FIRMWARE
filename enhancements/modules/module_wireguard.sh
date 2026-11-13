#!/bin/sh
# enhancements/modules/module_wireguard.sh
# Module: Isolated BoringTun WireGuard (wg1) Staging & Readiness Checks
# Guarantees: Never starts wg1 automatically and never touches production wg0.

set -u

_MOD_DIR="$(cd "$(dirname "$0")" && pwd)"
_COMMON=""
for _cand in "${_MOD_DIR}/../lib/module_common.sh" "${_MOD_DIR}/lib/module_common.sh"; do
    if [ -f "$_cand" ]; then
        _COMMON="$_cand"
        break
    fi
done
[ -n "$_COMMON" ] || { echo "ERROR: module_common.sh not found" >&2; exit 1; }
. "$_COMMON"

ACTION="${1:-status}"
TARGET_DIR="${2:-/tmp/enhancements}"
WG_DIR="${TARGET_DIR}/wireguard"
STATE_FILE=$(mc_state_file "$TARGET_DIR" "module_wireguard")

describe_mod() {
    echo "WireGuard wg1 isolated staging: Verifies isolated wg1 template/tooling (zero runtime wg0 impact)"
}

check_wg0_untouched() {
    if [ -f "${WG_DIR}/wg0.conf" ]; then
        echo "ERROR: Forbidden wg0 configuration detected inside enhancement dir!" >&2
        return 1
    fi
    return 0
}

stage_mod() {
    check_wg0_untouched || return 1
    mkdir -p "$WG_DIR" "${TARGET_DIR}/state" || return 1
    cat << 'EOF' > "${WG_DIR}/wg1_template.conf"
# RA82 Isolated WireGuard Test Interface (wg1)
# Production wg0 remains untouched on port 51820. wg1 binds strictly to UDP 51821 / table 101.
[Interface]
ListenPort = 51821
# PrivateKey = <GENERATE_AT_RUNTIME_DO_NOT_COMMIT>
EOF
    chmod 600 "${WG_DIR}/wg1_template.conf" || return 1

    cat << 'EOF' > "${WG_DIR}/wg1_manager.sh"
#!/bin/sh
set -u
case "${1:-status}" in
    status) echo "Isolated wg1 staging ready (port 51821, table 101; wg0 untouched)." ;;
    *) echo "Direct start/stop must use hardened performance/wireguard_rust/{deploy_wg1.sh,teardown_wg1.sh}" >&2; exit 1 ;;
esac
EOF
    chmod +x "${WG_DIR}/wg1_manager.sh" || return 1
    return 0
}

inspect_mod() {
    check_wg0_untouched || return 1
    echo "Inspecting module_wireguard isolation:"
    echo "  Target interface: wg1 (UDP 51821, routing table 101)"
    echo "  Protected production interface: wg0 (zero modification permitted)"
    if [ -d "$(resolve_path /sys/class/net/wg1)" ]; then
        echo "  [WARN] wg1 interface currently exists in netns/host"
    else
        echo "  [OK] wg1 interface absent (clean pre-trial state)"
    fi
    return 0
}

apply_mod() {
    check_wg0_untouched || return 1
    if [ ! -f "${WG_DIR}/wg1_template.conf" ] || [ ! -x "${WG_DIR}/wg1_manager.sh" ]; then
        stage_mod || return 1
    fi
    mkdir -p "${TARGET_DIR}/state" || return 1
    cat << 'EOF' > "$STATE_FILE"
OWNED_FILES=wg1_template.conf wg1_manager.sh
WG0_TOUCHED=0
APPLIED=1
EOF
    return 0
}

rollback_mod() {
    check_wg0_untouched || return 1
    if [ ! -f "$STATE_FILE" ]; then
        _tstate=$(mc_manifest_trial_state "$TARGET_DIR" 2>/dev/null || echo "")
        [ "$_tstate" = "staged" ] || [ "$_tstate" = "rolled_back" ] || {
            echo "ERROR: Missing $STATE_FILE during active rollback" >&2
            return 1
        }
    fi
    rm -f "${WG_DIR}/wg1_template.conf" "${WG_DIR}/wg1_manager.sh" "$STATE_FILE" || return 1
    if [ -d "$WG_DIR" ]; then
        rmdir "$WG_DIR" 2>/dev/null || true
    fi
    return 0
}

verify_mod() {
    check_wg0_untouched || return 1
    [ -f "$STATE_FILE" ] && [ -f "${WG_DIR}/wg1_template.conf" ] && [ -x "${WG_DIR}/wg1_manager.sh" ]
}

status_mod() {
    echo "  Module: module_wireguard"
    if [ -f "${WG_DIR}/wg1_template.conf" ]; then
        echo "    wg1_template.conf: STAGED (Port 51821; wg0 untouched)"
    else
        echo "    wg1_template.conf: NOT STAGED"
    fi
}

case "$ACTION" in
    describe) describe_mod ;;
    inspect) inspect_mod ;;
    stage) stage_mod ;;
    apply) apply_mod ;;
    rollback) rollback_mod ;;
    verify) verify_mod ;;
    status) status_mod ;;
    *) echo "Usage: $0 {describe|inspect|stage|apply|rollback|verify|status} [target_dir]" >&2; exit 1 ;;
esac
