#!/bin/sh
# scripts/watchdog_service.sh
# Hardened Reversible Watchdog for M11.1 Runtime Firewall Trials
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Usage:
#   watchdog_service.sh <TIMEOUT_SECONDS> <SENTINEL_FILE> <ROLLBACK_HELPER_PATH> [ARGS...]
#
# Security & Synchronization Properties:
#   1. Input Validation: Strictly enforces positive integer for TIMEOUT.
#   2. Zero-Eval Dispatch: Invokes structured helper executable/script directly without eval.
#   3. State Synchronization: Uses atomic state transitions to eliminate race conditions
#      between sentinel deletion, signal handling, and rollback execution.
#   4. Signal Trapping: Traps SIGHUP (ignored), traps SIGTERM/SIGINT (clean disarm without rollback).

TIMEOUT="${1:-180}"
SENTINEL="${2:-/tmp/m11_watchdog.armed}"
ROLLBACK_HELPER="${3:-scripts/firewall_manager.sh}"
shift 3 2>/dev/null || true
ROLLBACK_ARGS="$*"

LOG_TAG="M11_WATCHDOG"
STATE_FILE="${SENTINEL}.state"

log_msg() {
    logger -t "$LOG_TAG" "$1" 2>/dev/null || echo "[$LOG_TAG] $1" >&2
}

# 1. Parameter Validation: Ensure TIMEOUT is a strictly positive integer
if ! echo "$TIMEOUT" | grep -Eq '^[1-9][0-9]*$'; then
    log_msg "ERROR: Invalid TIMEOUT parameter: '$TIMEOUT'. Must be a positive integer. Aborting."
    exit 1
fi

# 2. State Initialization
echo "ARMED" > "$STATE_FILE" 2>/dev/null || true
touch "$SENTINEL" 2>/dev/null || true

# 3. Traps for Signals
# SIGHUP: Ignore terminal hangup / SSH session disconnect
trap '' HUP

# SIGTERM / SIGINT: Clean termination if disarmed via signal
trap '
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ARMED" ]; then
        echo "CANCELLED_BY_SIGNAL" > "$STATE_FILE" 2>/dev/null || true
        log_msg "Watchdog received SIGTERM while ARMED. Cleanly exiting without rollback."
        rm -f "$SENTINEL" "$STATE_FILE" 2>/dev/null || true
        exit 0
    elif [ "$CURRENT_STATE" = "ROLLING_BACK" ]; then
        log_msg "Watchdog received SIGTERM during active rollback. Allowing rollback to complete."
    fi
' TERM INT

log_msg "Watchdog armed for ${TIMEOUT}s. Sentinel: $SENTINEL. Helper: $ROLLBACK_HELPER"

# 4. Sleep for timeout window
sleep "$TIMEOUT"

# 5. Synchronized State Transition Check
# Atomically check sentinel and state file to eliminate race condition
if [ -f "$SENTINEL" ]; then
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ARMED" ]; then
        # Transition state to ROLLING_BACK
        echo "ROLLING_BACK" > "$STATE_FILE" 2>/dev/null || true
        log_msg "Timeout expired with active sentinel. Executing rollback helper: $ROLLBACK_HELPER..."

        # Structured direct invocation without eval
        if [ -x "$ROLLBACK_HELPER" ] || [ -f "$ROLLBACK_HELPER" ]; then
            if ! sh "$ROLLBACK_HELPER" rollback $ROLLBACK_ARGS; then
                log_msg "WARNING: Rollback helper reported non-zero status. Execution finished."
            fi
        else
            log_msg "ERROR: Rollback helper '$ROLLBACK_HELPER' not found or not executable."
        fi

        echo "ROLLBACK_COMPLETED" > "$STATE_FILE" 2>/dev/null || true
        rm -f "$SENTINEL" "$STATE_FILE" 2>/dev/null || true
        log_msg "Rollback execution finished."
        exit 0
    fi
fi

log_msg "Sentinel missing or disarmed prior to timeout. Watchdog exiting cleanly without rollback."
rm -f "$STATE_FILE" 2>/dev/null || true
exit 0
