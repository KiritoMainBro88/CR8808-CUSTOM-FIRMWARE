#!/bin/sh
# enhancements/modules/module_rps.sh
# Module: RPS & RFS SoftIRQ Balancing (CPU0 -> CPU1 offload)

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
# shellcheck source=../lib/module_common.sh
. "$_COMMON"

MOD_NAME="module_rps"
SPECS="req|/sys/class/net/eth0/queues/rx-0/rps_cpus|2
req|/proc/sys/net/core/rps_sock_flow_entries|16384
opt|/sys/class/net/eth1/queues/rx-0/rps_cpus|3
opt|/sys/class/net/br-lan/queues/rx-0/rps_cpus|3
opt|/sys/class/net/eth0/queues/rx-0/rps_flow_cnt|4096"

ACTION="${1:-status}"
TARGET_DIR="${2:-/tmp/enhancements}"

case "$ACTION" in
    describe) echo "RPS/RFS SoftIRQ balancing: Shifts eth0 rx-0 SoftIRQ to CPU1 (2) and snapshots all touched queues" ;;
    inspect) mc_kv_inspect "$MOD_NAME" "$SPECS" ;;
    stage) mc_kv_stage "$MOD_NAME" "$TARGET_DIR" ;;
    apply) mc_kv_apply "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    rollback) mc_kv_rollback "$MOD_NAME" "$TARGET_DIR" ;;
    verify) mc_kv_verify "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    status) mc_kv_status "$MOD_NAME" "$SPECS" ;;
    *) echo "Usage: $0 {describe|inspect|stage|apply|rollback|verify|status} [target_dir]" >&2; exit 1 ;;
esac
