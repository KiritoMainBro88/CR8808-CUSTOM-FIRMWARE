#!/bin/sh
# enhancements/modules/module_sysctl.sh
# Module: TCP & Netfilter Sysctl Tuning (Reversible Volatile Trial Only)

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

MOD_NAME="module_sysctl"
SPECS="req|/proc/sys/net/ipv4/tcp_fastopen|3
req|/proc/sys/net/ipv4/tcp_tw_reuse|1
req|/proc/sys/net/ipv4/tcp_fin_timeout|30
req|/proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established|86400"

ACTION="${1:-status}"
TARGET_DIR="${2:-/tmp/enhancements}"

case "$ACTION" in
    describe) echo "Sysctl networking tuning: Volatile TFO=3, tw_reuse=1, fin_timeout=30, conntrack_established=86400" ;;
    inspect) mc_kv_inspect "$MOD_NAME" "$SPECS" ;;
    stage) mc_kv_stage "$MOD_NAME" "$TARGET_DIR" ;;
    apply) mc_kv_apply "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    rollback) mc_kv_rollback "$MOD_NAME" "$TARGET_DIR" ;;
    verify) mc_kv_verify "$MOD_NAME" "$TARGET_DIR" "$SPECS" ;;
    status) mc_kv_status "$MOD_NAME" "$SPECS" ;;
    *) echo "Usage: $0 {describe|inspect|stage|apply|rollback|verify|status} [target_dir]" >&2; exit 1 ;;
esac
