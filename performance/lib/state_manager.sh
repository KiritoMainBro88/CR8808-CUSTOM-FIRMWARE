#!/bin/sh
# performance/lib/state_manager.sh
# Transaction and State Manager for RA82 Optimization Framework
# Compatible with POSIX /bin/sh (BusyBox ash, dash, bash)

set -u

if [ -z "${_COMMON_SH_LOADED:-}" ]; then
    _STATE_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "${_STATE_LIB_DIR}/common.sh" ]; then
        . "${_STATE_LIB_DIR}/common.sh"
    elif [ -f "${_STATE_LIB_DIR}/lib/common.sh" ]; then
        . "${_STATE_LIB_DIR}/lib/common.sh"
    fi
fi

ACTIVE_LIST="${STATE_DIR}/active_profiles.list"
LOCK_FILE="${STATE_DIR}/framework.lock"

acquire_lock() {
    ensure_state_dir
    _retries=5
    while [ "$_retries" -gt 0 ]; do
        if mkdir "${LOCK_FILE}.d" 2>/dev/null; then
            echo "$$" > "${LOCK_FILE}.d/pid"
            return 0
        fi
        # Check for stale lock
        if [ -f "${LOCK_FILE}.d/pid" ]; then
            _lpid=$(cat "${LOCK_FILE}.d/pid" 2>/dev/null || echo "")
            if [ -n "$_lpid" ] && ! kill -0 "$_lpid" 2>/dev/null; then
                rm -rf "${LOCK_FILE}.d" 2>/dev/null || true
                continue
            fi
        fi
        sleep 1
        _retries=$((_retries - 1))
    done
    log_err "Failed to acquire framework lock (${LOCK_FILE})"
    return 1
}

release_lock() {
    rm -rf "${LOCK_FILE}.d" 2>/dev/null || true
}

# Record a profile as active
record_active_profile() {
    _profile="$1"
    ensure_state_dir
    if [ -f "$ACTIVE_LIST" ]; then
        if grep -q "^${_profile}$" "$ACTIVE_LIST" 2>/dev/null; then
            return 0
        fi
    fi
    echo "$_profile" >> "$ACTIVE_LIST"
}

# Remove a profile from active list
remove_active_profile() {
    _profile="$1"
    if [ -f "$ACTIVE_LIST" ]; then
        grep -v "^${_profile}$" "$ACTIVE_LIST" > "${ACTIVE_LIST}.tmp" 2>/dev/null || true
        mv "${ACTIVE_LIST}.tmp" "$ACTIVE_LIST"
    fi
}

# Check if a profile is active
is_profile_active() {
    _profile="$1"
    if [ -f "$ACTIVE_LIST" ]; then
        grep -q "^${_profile}$" "$ACTIVE_LIST" 2>/dev/null
        return $?
    fi
    return 1
}

# List all active profiles in order
list_active_profiles() {
    if [ -f "$ACTIVE_LIST" ]; then
        cat "$ACTIVE_LIST"
    fi
}
