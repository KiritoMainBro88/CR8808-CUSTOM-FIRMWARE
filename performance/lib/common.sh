#!/bin/sh
# performance/lib/common.sh
# Shared functions for RA82 Performance Optimization Framework
# Compatible with POSIX /bin/sh (BusyBox ash, dash, bash)

set -u

_COMMON_SH_LOADED=1

# Base paths (supports mock root for hermetic testing in WSL/PC)
MOCK_ROOT="${MOCK_ROOT:-}"
STATE_DIR="${STATE_DIR:-/tmp/performance_state}"

if [ -n "$MOCK_ROOT" ]; then
    case "$STATE_DIR" in
        "$MOCK_ROOT"*) ;;
        *) STATE_DIR="${MOCK_ROOT}${STATE_DIR}" ;;
    esac
fi

# Ensure state directory exists
ensure_state_dir() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
}

# Logging helpers
log_info() {
    echo "[INFO]  $*"
}

log_warn() {
    echo "[WARN]  $*" >&2
}

log_err() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[OK]    $*"
}

# Resolve sysctl parameter to proc path
# Example: net.ipv4.tcp_rmem -> /proc/sys/net/ipv4/tcp_rmem
sysctl_to_proc() {
    _param="$1"
    _proc_path=$(echo "$_param" | tr '.' '/')
    echo "${MOCK_ROOT}/proc/sys/${_proc_path}"
}

# Read a sysctl parameter value
# Returns standard output trimmed of extra trailing newlines
read_sysctl() {
    _param="$1"
    _file=$(sysctl_to_proc "$_param")
    if [ -f "$_file" ]; then
        cat "$_file" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//'
        echo ""
        return 0
    elif [ -z "$MOCK_ROOT" ] && command -v sysctl >/dev/null 2>&1; then
        sysctl -n "$_param" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

# Write a sysctl parameter value
write_sysctl() {
    _param="$1"
    _val="$2"
    _file=$(sysctl_to_proc "$_param")
    if [ -n "$MOCK_ROOT" ]; then
        mkdir -p "$(dirname "$_file")" 2>/dev/null || true
        printf '%s\n' "$_val" > "$_file" 2>/dev/null || return 1
        return 0
    elif [ -w "$_file" ]; then
        printf '%s\n' "$_val" > "$_file" 2>/dev/null || return 1
        return 0
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -w "${_param}=${_val}" >/dev/null 2>&1 || return 1
        return 0
    fi
    return 1
}

# Resolve sysfs path (supports MOCK_ROOT)
sysfs_path() {
    _path="$1"
    case "$_path" in
        "$MOCK_ROOT"*) echo "$_path" ;;
        *) echo "${MOCK_ROOT}${_path}" ;;
    esac
}

# Read sysfs path
read_sysfs() {
    _path="$1"
    _full=$(sysfs_path "$_path")
    if [ -f "$_full" ]; then
        cat "$_full" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//'
        echo ""
        return 0
    fi
    return 1
}

# Write sysfs path
write_sysfs() {
    _path="$1"
    _val="$2"
    _full=$(sysfs_path "$_path")
    if [ -n "$MOCK_ROOT" ]; then
        mkdir -p "$(dirname "$_full")" 2>/dev/null || true
        printf '%s\n' "$_val" > "$_full" 2>/dev/null || return 1
        return 0
    elif [ -w "$_full" ]; then
        printf '%s\n' "$_val" > "$_full" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

# State management functions
get_state_file() {
    _profile="$1"
    echo "${STATE_DIR}/${_profile}.state"
}

has_state() {
    _profile="$1"
    _file=$(get_state_file "$_profile")
    [ -f "$_file" ]
}

# Save a key=value pair to state snapshot
# Encodes value to safe string
save_state_kv() {
    _profile="$1"
    _key="$2"
    _val="$3"
    ensure_state_dir
    _file=$(get_state_file "$_profile")
    printf '%s=%s\n' "$_key" "$_val" >> "$_file"
}

# Read a saved value by key from state snapshot
get_saved_state_kv() {
    _profile="$1"
    _key="$2"
    _file=$(get_state_file "$_profile")
    if [ -f "$_file" ]; then
        grep "^${_key}=" "$_file" 2>/dev/null | head -n 1 | cut -d'=' -f2-
        return 0
    fi
    return 1
}

# Clear state snapshot
clear_state() {
    _profile="$1"
    _file=$(get_state_file "$_profile")
    rm -f "$_file" 2>/dev/null || true
}
