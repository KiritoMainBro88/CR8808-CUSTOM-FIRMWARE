#!/bin/sh
# scripts/watchdog_service.sh
# Hardened Reversible Watchdog for M11.1 Runtime Firewall Trials
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Usage:
#   watchdog_service.sh <TIMEOUT_SECONDS> <SENTINEL_FILE> <ROLLBACK_HELPER_PATH> [ARGS...]
#
# Security & Integrity Guarantees (Directive M11.1.0.4):
#   1. Timeout Validation: Strictly integer between 1 and 86400 (BusyBox sleep compatible).
#   2. Sleep Integrity: Non-zero sleep exit aborts immediately with SLEEP_FAILED (no premature rollback).
#   3. Mutual Exclusion: Atomic directory lock prevents duplicate concurrent watchdogs.
#   4. State Preservation: Failures set ROLLBACK_FAILED and preserve sentinel + error evidence.
#   5. Retry Logic: 3 attempts with 1s backoff for transient helper failures.
#   6. Zero-Eval Parameter Preservation: Retains exact positional parameters via "$@".

TIMEOUT="${1:-}"
SENTINEL="${2:-/tmp/m11_watchdog.armed}"
ROLLBACK_HELPER="${3:-scripts/firewall_manager.sh}"

LOG_TAG="M11_WATCHDOG"
STATE_FILE="${SENTINEL}.state"
LOCK_DIR="${SENTINEL}.lock"
ERROR_LOG="${SENTINEL}.error.log"

log_msg() {
    logger -t "$LOG_TAG" "$1" 2>/dev/null || echo "[$LOG_TAG] $1" >&2
}

# 1. Parameter Validation: Ensure TIMEOUT is an integer within 1..86400 seconds
if ! echo "$TIMEOUT" | grep -Eq '^[1-9][0-9]*$' || [ "$TIMEOUT" -gt 86400 ]; then
    log_msg "ERROR: Invalid TIMEOUT parameter: '$TIMEOUT'. Must be an integer between 1 and 86400. Aborting."
    exit 1
fi

# Shift the first 3 parameters so "$@" contains ONLY the rollback arguments
shift 3 2>/dev/null || true

# 2. Mutual Exclusion: Atomic Directory Lock
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    EXISTING_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "UNKNOWN")
    log_msg "ERROR: Another watchdog instance is already active for '$SENTINEL' (PID: $EXISTING_PID). Aborting."
    exit 1
fi
echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || true

# 3. Sentinel & State File Initialization
if ! touch "$SENTINEL" 2>/dev/null || ! echo "ARMED" > "$STATE_FILE" 2>/dev/null; then
    log_msg "ERROR: Failed to initialize sentinel or state file at '$SENTINEL'. Aborting."
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    exit 1
fi

# 4. Traps for Signals
# SIGHUP: Ignore terminal hangup / SSH session disconnect
trap '' HUP

# SIGTERM / SIGINT: Clean termination if disarmed via signal
trap '
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ARMED" ]; then
        echo "CANCELLED_BY_SIGNAL" > "$STATE_FILE" 2>/dev/null || true
        log_msg "Watchdog received SIGTERM while ARMED. Cleanly exiting without rollback."
        rm -f "$SENTINEL" "$STATE_FILE" 2>/dev/null || true
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        exit 0
    elif [ "$CURRENT_STATE" = "ROLLING_BACK" ]; then
        log_msg "Watchdog received SIGTERM during active rollback. Allowing rollback to complete."
    fi
' TERM INT

log_msg "Watchdog armed for ${TIMEOUT}s. Sentinel: $SENTINEL. Helper: $ROLLBACK_HELPER"

# 5. Sleep for timeout window with failure detection
if ! sleep "$TIMEOUT"; then
    log_msg "CRITICAL: Sleep command failed or was interrupted unexpectedly. Aborting without rollback to prevent premature reversion."
    echo "SLEEP_FAILED" > "$STATE_FILE" 2>/dev/null || true
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    exit 1
fi

# 6. Synchronized State Transition & Rollback Execution
if [ -f "$SENTINEL" ]; then
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ARMED" ]; then
        echo "ROLLING_BACK" > "$STATE_FILE" 2>/dev/null || true
        log_msg "Timeout expired with active sentinel. Executing rollback helper: $ROLLBACK_HELPER..."

        ROLLBACK_SUCCESS=0
        ATTEMPT=1
        MAX_ATTEMPTS=3

        while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
            if [ -x "$ROLLBACK_HELPER" ] || [ -f "$ROLLBACK_HELPER" ]; then
                if sh "$ROLLBACK_HELPER" rollback "$@"; then
                    ROLLBACK_SUCCESS=1
                    break
                else
                    log_msg "WARN: Rollback helper failed attempt $ATTEMPT of $MAX_ATTEMPTS."
                    echo "Attempt $ATTEMPT failed at $(date 2>/dev/null || true)" >> "$ERROR_LOG"
                fi
            else
                log_msg "CRITICAL: Rollback helper '$ROLLBACK_HELPER' not found or not executable."
                echo "Rollback helper '$ROLLBACK_HELPER' missing at $(date 2>/dev/null || true)" >> "$ERROR_LOG"
                break
            fi
            ATTEMPT=$((ATTEMPT + 1))
            sleep 1
        done

        if [ "$ROLLBACK_SUCCESS" -eq 1 ]; then
            echo "ROLLBACK_COMPLETED" > "$STATE_FILE" 2>/dev/null || true
            rm -f "$SENTINEL" "$STATE_FILE" "$ERROR_LOG" 2>/dev/null || true
            rm -rf "$LOCK_DIR" 2>/dev/null || true
            log_msg "Rollback execution verified successful."
            exit 0
        else
            echo "ROLLBACK_FAILED" > "$STATE_FILE" 2>/dev/null || true
            rm -rf "$LOCK_DIR" 2>/dev/null || true
            log_msg "CRITICAL: Rollback execution FAILED after $MAX_ATTEMPTS attempts! Sentinel and state preserved for forensic diagnosis."
            exit 1
        fi
    fi
fi

log_msg "Sentinel missing or disarmed prior to timeout. Watchdog exiting cleanly without rollback."
rm -f "$STATE_FILE" 2>/dev/null || true
rm -rf "$LOCK_DIR" 2>/dev/null || true
exit 0
