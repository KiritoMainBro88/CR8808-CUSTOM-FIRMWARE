#!/bin/sh
# performance/framework.sh
# ==============================================================================
# Management CLI: RA82 Modular Performance Optimization Framework
# Workstream G: Automated Optimization Framework
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53, Linux 4.4.60)
#
# Supported Commands:
#   sh performance/framework.sh list
#   sh performance/framework.sh audit [profile]
#   sh performance/framework.sh apply <profile> [--confirm-experimental]
#   sh performance/framework.sh rollback <profile>
#   sh performance/framework.sh rollback_all
#   sh performance/framework.sh verify [profile]
#
# Safety Policy:
#   - NEVER apply all optimizations monolithically; each profile is independent.
#   - Experimental/Hold profiles require explicit --confirm-experimental flag.
#   - Atomic apply with mandatory pre-apply state snapshotting.
#   - Automatic instantaneous rollback if post-apply verification fails.
#   - Reversible without device reboot or persistent firmware modification.
# ==============================================================================

set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${BASE_DIR}/lib"
PROFILES_DIR="${BASE_DIR}/profiles"

. "${LIB_DIR}/common.sh"
. "${LIB_DIR}/state_manager.sh"

get_profile_path() {
    _prof="$1"
    # Allow passing name with or without .sh
    _clean=$(echo "$_prof" | sed 's/\.sh$//')
    echo "${PROFILES_DIR}/${_clean}.sh"
}

get_profile_status() {
    _prof="$1"
    _script=$(get_profile_path "$_prof")
    _name=$(basename "$_script" .sh)

    if has_state "$_name"; then
        if sh "$_script" verify >/dev/null 2>&1; then
            echo "APPLIED"
        else
            echo "DEGRADED"
        fi
    else
        _exp=$(grep "^PROFILE_STATUS=" "$_script" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        if [ "$_exp" = "EXPERIMENTAL_HOLD" ]; then
            echo "EXPERIMENTAL_HOLD"
        elif sh "$_script" verify >/dev/null 2>&1; then
            echo "MATCH_PROPOSED"
        else
            echo "BASELINE"
        fi
    fi
}

cmd_list() {
    echo "================================================================================"
    printf "%-22s %-18s %-38s\n" "PROFILE" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------------------"
    for script in "$PROFILES_DIR"/*.sh; do
        if [ -f "$script" ]; then
            _name=$(basename "$script" .sh)
            _status=$(get_profile_status "$_name")
            _desc=$(grep "^PROFILE_DESC=" "$script" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "Optimization module")
            printf "%-22s %-18s %-38s\n" "$_name" "$_status" "$_desc"
        fi
    done
    echo "================================================================================"
    echo "Active Profiles Managed: $(list_active_profiles | tr '\n' ' ')"
    echo ""
}

cmd_audit() {
    _target="${1:-all}"
    if [ "$_target" = "all" ]; then
        log_info "Executing system-wide performance audit across all profiles..."
        for script in "$PROFILES_DIR"/*.sh; do
            if [ -f "$script" ]; then
                echo "--------------------------------------------------------------------------------"
                sh "$script" audit
            fi
        done
        echo "--------------------------------------------------------------------------------"
    else
        _script=$(get_profile_path "$_target")
        if [ ! -f "$_script" ]; then
            log_err "Profile '$_target' not found in $PROFILES_DIR"
            return 1
        fi
        sh "$_script" audit
    fi
}

cmd_apply() {
    _target="${1:-}"
    _flag="${2:-}"

    if [ -z "$_target" ]; then
        log_err "Usage: $0 apply <profile> [--confirm-experimental]"
        log_err "Monolithic apply is forbidden. Each profile must be independently applied."
        return 1
    fi

    _script=$(get_profile_path "$_target")
    _name=$(basename "$_script" .sh)

    if [ ! -f "$_script" ]; then
        log_err "Profile '$_target' not found in $PROFILES_DIR"
        return 1
    fi

    # Check for experimental hold
    _exp=$(grep "^PROFILE_STATUS=" "$_script" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
    if [ "$_exp" = "EXPERIMENTAL_HOLD" ]; then
        if [ "$_flag" != "--confirm-experimental" ] && [ "${ALLOW_EXPERIMENTAL:-0}" != "1" ]; then
            log_err "Profile '$_name' is marked EXPERIMENTAL/HOLD."
            log_err "Applying it requires service restart (SIGHUP does not re-read main config) and RAM budget sign-off."
            log_err "To confirm execution on testbed, pass: $0 apply $_name --confirm-experimental"
            return 1
        fi
        log_warn "Experimental profile '$_name' confirmed via execution flag."
    fi

    if ! acquire_lock; then
        return 1
    fi

    log_info "Initiating atomic apply for profile: $_name"
    if sh "$_script" apply; then
        record_active_profile "$_name"
        log_success "Profile '$_name' applied and verified successfully."
        release_lock
        return 0
    else
        log_err "Profile '$_name' apply failed or was rolled back."
        remove_active_profile "$_name"
        release_lock
        return 1
    fi
}

cmd_rollback() {
    _target="${1:-}"
    if [ -z "$_target" ]; then
        log_err "Usage: $0 rollback <profile>"
        return 1
    fi

    _script=$(get_profile_path "$_target")
    _name=$(basename "$_script" .sh)

    if [ ! -f "$_script" ]; then
        log_err "Profile '$_target' not found in $PROFILES_DIR"
        return 1
    fi

    if ! acquire_lock; then
        return 1
    fi

    log_info "Initiating atomic rollback for profile: $_name"
    if sh "$_script" rollback; then
        remove_active_profile "$_name"
        log_success "Profile '$_name' rolled back successfully."
        release_lock
        return 0
    else
        log_err "Profile '$_name' rollback encountered errors."
        release_lock
        return 1
    fi
}

cmd_rollback_all() {
    if ! acquire_lock; then
        return 1
    fi

    log_info "Rolling back ALL active profiles..."
    _active=$(list_active_profiles)

    if [ -z "$_active" ]; then
        log_info "No active profiles recorded. Checking for orphaned state files..."
        for sfile in "${STATE_DIR}"/*.state; do
            if [ -f "$sfile" ]; then
                _name=$(basename "$sfile" .state)
                _script=$(get_profile_path "$_name")
                if [ -f "$_script" ]; then
                    log_info "Rolling back orphaned state for $_name"
                    sh "$_script" rollback || true
                fi
            fi
        done
        release_lock
        log_success "Rollback all completed: system clean."
        return 0
    fi

    # Roll back in reverse order
    _rev_list=$(echo "$_active" | awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}')

    _errors=0
    for prof in $_rev_list; do
        log_info "Rolling back active profile: $prof"
        _script=$(get_profile_path "$prof")
        if [ -f "$_script" ]; then
            if sh "$_script" rollback; then
                remove_active_profile "$prof"
            else
                log_err "Rollback failed for $prof"
                _errors=$((_errors + 1))
            fi
        fi
    done

    release_lock
    if [ "$_errors" -eq 0 ]; then
        log_success "All active profiles safely rolled back to baseline."
        return 0
    else
        log_err "Rollback all completed with $_errors errors."
        return 1
    fi
}

cmd_verify() {
    _target="${1:-all}"
    if [ "$_target" = "all" ]; then
        log_info "Verifying all active profiles..."
        _active=$(list_active_profiles)
        if [ -z "$_active" ]; then
            log_info "No active profiles are currently registered."
            return 0
        fi

        _failed=0
        for prof in $_active; do
            _script=$(get_profile_path "$prof")
            if [ -f "$_script" ]; then
                if sh "$_script" verify >/dev/null 2>&1; then
                    log_success "Active profile '$prof': VERIFIED"
                else
                    log_err "Active profile '$prof': VERIFICATION FAILED (DEGRADED)"
                    _failed=$((_failed + 1))
                fi
            fi
        done

        if [ "$_failed" -eq 0 ]; then
            log_success "All registered profiles match expected applied states."
            return 0
        else
            log_err "$_failed profile(s) failed verification."
            return 1
        fi
    else
        _script=$(get_profile_path "$_target")
        _name=$(basename "$_script" .sh)
        if [ ! -f "$_script" ]; then
            log_err "Profile '$_target' not found."
            return 1
        fi
        if sh "$_script" verify; then
            log_success "Profile '$_name': VERIFIED"
            return 0
        else
            log_err "Profile '$_name': VERIFICATION FAILED"
            return 1
        fi
    fi
}

# Entrypoint
ACTION="${1:-list}"
shift || true

case "$ACTION" in
    list) cmd_list ;;
    audit) cmd_audit "$@" ;;
    apply) cmd_apply "$@" ;;
    rollback) cmd_rollback "$@" ;;
    rollback_all) cmd_rollback_all ;;
    verify) cmd_verify "$@" ;;
    *)
        echo "Usage: $0 {list|audit [profile]|apply <profile> [--confirm-experimental]|rollback <profile>|rollback_all|verify [profile]}"
        exit 1
        ;;
esac
