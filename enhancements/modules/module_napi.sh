#!/bin/sh
# enhancements/modules/module_napi.sh
# Module: NAPI Network Backlog & Poll Budget Optimization

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

MOD_NAME="module_napi"
SPECS="req|/proc/sys/net/core/netdev_max_backlog|16384
req|/proc/sys/net/core/netdev_budget|600
opt|/proc/sys/net/core/netdev_budget_usecs|4000"

ACTION="${1:-status}"
TARGET_DIR="${2:-/tmp/enhancements}"

case "$ACTION" in
    describe) echo "NAPI budget tuning: Expands netdev_max_backlog to 16384, netdev_budget to 600, and optional budget_usecs" ;;
    inspect) mc_kv_inspect "$MOD_NAME" "$SPECS" ;;
    stage) mc_kv_stage "$MOD_NAME" "$TARGET_DIR" ;;
    apply) mc_kv_apply "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    rollback) mc_kv_rollback "$MOD_NAME" "$TARGET_DIR" ;;
    verify) mc_kv_verify "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    status) mc_kv_status "$MOD_NAME" "$SPECS" ;;
    *) echo "Usage: $0 {describe|inspect|stage|apply|rollback|verify|status} [target_dir]" >&2; exit 1 ;;
esac
