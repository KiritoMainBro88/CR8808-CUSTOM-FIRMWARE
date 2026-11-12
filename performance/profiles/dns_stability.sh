#!/bin/sh
# performance/profiles/dns_stability.sh
# ==============================================================================
# Profile: DNS Stability, Cache Sizing & Resolver Tuning (EXPERIMENTAL / ON_HOLD)
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
# Status: EXPERIMENTAL / ON_HOLD (Requires explicit confirmation; live execution held)
#
# SPECIFICATION & ARCHITECTURAL DOCUMENTATION:
# ------------------------------------------------------------------------------
# 1. ACCURATE DNSMASQ SIGHUP SEMANTICS (CRITICAL ARCHITECTURAL CORRECTION):
#    - Official dnsmasq manpage & source mechanics:
#      SIGHUP does NOT reload main configuration files (dnsmasq.conf or --conf-dir).
#      Upon receiving SIGHUP, dnsmasq:
#        a) Flushes its in-memory DNS cache.
#        b) Re-reads /etc/hosts, /etc/ethers, and --dhcp-hostsfile/--hostsdir.
#        c) Re-reads /etc/resolv.conf (if --no-poll is set).
#        d) Invokes lease change scripts for existing DHCP leases.
#    - To modify structural parameters like 'cache-size', 'dns-forward-max',
#      or load new snippet files, dnsmasq MUST BE RESTARTED (SIGTERM/kill followed
#      by respawn or /etc/init.d/dnsmasq restart).
#    - A daemon restart closes listening sockets and creates a brief (~50-200ms)
#      window where client DNS queries or DHCP renewals can be dropped.
#      Claims of "guaranteed zero DHCP disruption" were inaccurate and are retracted.
#
# 2. RAM BUDGET CONSTRAINTS ON RA82:
#    - The baseline audit recorded MemAvailable at only ~10.1 MB (5.5% of 182 MB).
#    - Unverified large cache expansion (e.g. 2,048 entries / 512 forward slots)
#      could risk page allocation failure under bursty slab allocation.
#    - Target values are held at conservative trial figures (cache-size=300,
#      dns-forward-max=150) pending live RAM budget sign-off.
#
# 3. PARAMETERS & VALUES:
#    - dnsmasq cache-size:
#        Baseline: 150 -> Conservative Trial: 300 (Deferred: 2048 held for RAM audit)
#    - dnsmasq dns-forward-max:
#        Baseline: 150 -> Conservative Trial: 150 (Deferred: 512 held for RAM audit)
#    - dnsmasq min-cache-ttl:
#        Baseline: 0 -> Proposed: 300 (Guarantees 5m TTL; absorbs upstream micro-outages)
#    - dnsmasq neg-ttl:
#        Baseline: 0 -> Proposed: 60 (Caches negative NXDOMAIN responses for 60s)
#    - libc resolver options (/etc/resolv.conf):
#        Baseline: default (timeout:5 attempts:2) -> Proposed: options timeout:1 attempts:2
#
# 4. SAFETY POLICY:
#    - Marked EXPERIMENTAL/HOLD. Framework requires --confirm-experimental flag.
#    - Offline configuration generation, state capture, and rollback fully supported.
# ==============================================================================

set -u

PROFILE_NAME="dns_stability"
PROFILE_DESC="DNS Cache Sizing & Resolver Tuning [EXPERIMENTAL/HOLD]"
PROFILE_STATUS="EXPERIMENTAL_HOLD"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_LIB="${SCRIPT_DIR}/../lib"
. "${FRAMEWORK_LIB}/common.sh"

# Conservative trial defaults (2048/512 held until RAM budget verified)
PROPOSED_CACHE_SIZE="${PROPOSED_CACHE_SIZE:-300}"
PROPOSED_FORWARD_MAX="${PROPOSED_FORWARD_MAX:-150}"
PROPOSED_MIN_CACHE_TTL="${PROPOSED_MIN_CACHE_TTL:-300}"
PROPOSED_NEG_TTL="${PROPOSED_NEG_TTL:-60}"
PROPOSED_RESOLV_OPTIONS="${PROPOSED_RESOLV_OPTIONS:-options timeout:1 attempts:2}"

SNIPPET_FILE="/etc/dnsmasq.d/10-dns-stability.conf"
RESOLV_FILE="/tmp/resolv.conf.d/options.conf"

info() {
    cat << EOF
Profile: dns_stability
Status: EXPERIMENTAL / ON_HOLD (Requires confirmation flag --confirm-experimental)
Description: DNS Cache Sizing, Concurrency & Resolver Timeout Tuning
Parameters:
  - cache-size: 150 -> ${PROPOSED_CACHE_SIZE} (Conservative trial; 2048 held for RAM audit)
  - dns-forward-max: 150 -> ${PROPOSED_FORWARD_MAX} (512 held for RAM audit)
  - min-cache-ttl: 0 -> ${PROPOSED_MIN_CACHE_TTL}s (Absorbs upstream ISP DNS micro-outages)
  - neg-ttl: 0 -> ${PROPOSED_NEG_TTL}s (Suppresses repeated NXDOMAIN floods)
  - resolver options: ${PROPOSED_RESOLV_OPTIONS} (Accelerates upstream failover)
Technical SIGHUP Semantics:
  SIGHUP only flushes cache and reloads hosts/resolv.conf. It does NOT reload
  main configuration or new cache-size parameters. Full reload requires service
  restart with potential momentary socket interruption.
RAM Overhead: ~25 KiB (conservative 300 entries) vs ~90 KiB (2048 entries)
Safety Gate: Blocked from automatic framework apply. Manual confirmation required.
EOF
}

audit() {
    log_info "Auditing profile: ${PROFILE_NAME} [Status: ${PROFILE_STATUS}]"
    _snippet=$(read_conf "$SNIPPET_FILE" 2>/dev/null || echo "NOT_PRESENT")
    echo "  [config] $SNIPPET_FILE:"
    if [ "$_snippet" = "NOT_PRESENT" ]; then
        echo "    Status: NOT APPLIED (Default factory dnsmasq configuration active)"
    else
        echo "$_snippet" | sed 's/^/    /'
    fi

    _resolv=$(read_conf "$RESOLV_FILE" 2>/dev/null || echo "NOT_PRESENT")
    echo "  [resolver] $RESOLV_FILE: $_resolv"
}

apply() {
    log_info "Applying profile: ${PROFILE_NAME} (Offline config generation & state snapshot)"
    ensure_state_dir

    if has_state "$PROFILE_NAME"; then
        log_warn "State snapshot already exists for ${PROFILE_NAME}. Rollback first before re-applying."
        return 1
    fi

    # Snapshot current state
    _orig_snippet=$(read_conf "$SNIPPET_FILE" 2>/dev/null || echo "")
    _orig_resolv=$(read_conf "$RESOLV_FILE" 2>/dev/null || echo "")

    save_state_kv "$PROFILE_NAME" "orig.snippet.exists" "$([ -n "$_orig_snippet" ] && echo 1 || echo 0)"
    if [ -n "$_orig_snippet" ]; then
        save_state_kv "$PROFILE_NAME" "orig.snippet.content" "$(echo "$_orig_snippet" | tr '\n' ' ')"
    fi

    save_state_kv "$PROFILE_NAME" "orig.resolv.exists" "$([ -n "$_orig_resolv" ] && echo 1 || echo 0)"
    if [ -n "$_orig_resolv" ]; then
        save_state_kv "$PROFILE_NAME" "orig.resolv.content" "$(echo "$_orig_resolv" | tr '\n' ' ')"
    fi

    # Generate conservative dnsmasq stability configuration
    _config_body=$(cat << EOF
# Auto-generated by RA82 Performance Framework: dns_stability
# Note: Full activation requires daemon restart; SIGHUP only flushes cache.
cache-size=${PROPOSED_CACHE_SIZE}
dns-forward-max=${PROPOSED_FORWARD_MAX}
min-cache-ttl=${PROPOSED_MIN_CACHE_TTL}
neg-ttl=${PROPOSED_NEG_TTL}
EOF
)

    if ! write_conf "$SNIPPET_FILE" "$_config_body"; then
        log_err "Failed to write dnsmasq configuration snippet to $SNIPPET_FILE"
        rollback
        return 1
    fi

    # Generate resolver options
    if ! write_conf "$RESOLV_FILE" "$PROPOSED_RESOLV_OPTIONS"; then
        log_warn "Failed to write resolver options to $RESOLV_FILE (non-fatal)"
    fi

    # Note: On live device, do NOT restart dnsmasq automatically.
    # SIGHUP flushes cache but does not re-read cache-size.
    if [ -z "$MOCK_ROOT" ]; then
        log_warn "Notice: Written snippet to $SNIPPET_FILE. Daemon restart deferred to maintain live stability."
    fi

    if verify; then
        log_success "Profile ${PROFILE_NAME} applied successfully (state snapshot preserved)."
        return 0
    else
        log_err "Profile ${PROFILE_NAME} verification failed after apply. Initiating automatic rollback."
        rollback
        return 1
    fi
}

rollback() {
    log_info "Rolling back profile: ${PROFILE_NAME}"
    _state_file=$(get_state_file "$PROFILE_NAME")
    if [ ! -f "$_state_file" ]; then
        log_warn "No state file found for ${PROFILE_NAME}. Nothing to rollback."
        return 0
    fi

    _snippet_exists=$(get_saved_state_kv "$PROFILE_NAME" "orig.snippet.exists" || echo "0")
    if [ "$_snippet_exists" = "1" ]; then
        _orig_content=$(get_saved_state_kv "$PROFILE_NAME" "orig.snippet.content" || echo "")
        write_conf "$SNIPPET_FILE" "$_orig_content" || true
    else
        _full_snip=$(conf_path "$SNIPPET_FILE")
        rm -f "$_full_snip" 2>/dev/null || true
    fi

    _resolv_exists=$(get_saved_state_kv "$PROFILE_NAME" "orig.resolv.exists" || echo "0")
    if [ "$_resolv_exists" = "1" ]; then
        _orig_resolv=$(get_saved_state_kv "$PROFILE_NAME" "orig.resolv.content" || echo "")
        write_conf "$RESOLV_FILE" "$_orig_resolv" || true
    else
        _full_res=$(conf_path "$RESOLV_FILE")
        rm -f "$_full_res" 2>/dev/null || true
    fi

    clear_state "$PROFILE_NAME"
    log_success "Profile ${PROFILE_NAME} rolled back successfully."
    return 0
}

verify() {
    _content=$(read_conf "$SNIPPET_FILE" 2>/dev/null || echo "")
    if [ -z "$_content" ]; then
        return 1
    fi

    echo "$_content" | grep -q "cache-size=${PROPOSED_CACHE_SIZE}" || return 1
    echo "$_content" | grep -q "dns-forward-max=${PROPOSED_FORWARD_MAX}" || return 1
    echo "$_content" | grep -q "min-cache-ttl=${PROPOSED_MIN_CACHE_TTL}" || return 1
    echo "$_content" | grep -q "neg-ttl=${PROPOSED_NEG_TTL}" || return 1

    _res_content=$(read_conf "$RESOLV_FILE" 2>/dev/null || echo "")
    if [ -n "$_res_content" ]; then
        echo "$_res_content" | grep -q "timeout:1" || return 1
    fi

    return 0
}

ACTION="${1:-info}"
case "$ACTION" in
    info) info ;;
    audit) audit ;;
    apply) apply ;;
    rollback) rollback ;;
    verify) verify ;;
    *)
        echo "Usage: $0 {info|audit|apply|rollback|verify}"
        exit 1
        ;;
esac
