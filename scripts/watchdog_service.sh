#!/bin/sh
# scripts/watchdog_service.sh
# Hardened Reversible Watchdog for M11.1 Runtime Firewall Trials
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Usage:
#   watchdog_service.sh <TIMEOUT_SECONDS> <SENTINEL_FILE> <ROLLBACK_HELPER_PATH> [ARGS...]
#   watchdog_service.sh disarm <SENTINEL_FILE>
#
# Security & Integrity Guarantees (Directive M11.1.0.5):
#   1. Input Verification: Rejects missing arguments ($# < 3).
#   2. Timeout Validation: Strictly integer between 1 and 86400 (BusyBox sleep compatible).
#   3. Mutual Exclusion & Anti-Overwrite: Directory lock and rejection of unhandled SLEEP/ROLLBACK_FAILED states.
#   4. Atomic Transition Lock: Shared transition lock prevents race condition between disarm and rollback.
#   5. Verified State Preservation: Failures set ROLLBACK_FAILED and preserve sentinel + error evidence.
#   6. Retry Logic: 3 attempts with 1s backoff for transient helper failures.
#   7. Zero-Eval Parameter Preservation: Retains exact positional parameters via "$@".

# Handle first-class 'disarm' action with transition lock
if [ "$1" = "disarm" ]; then
    SENTINEL="${2:-/tmp/m11_watchdog.armed}"
    STATE_FILE="${SENTINEL}.state"
    LOCK_DIR="${SENTINEL}.lock"
    TRANS_LOCK="${SENTINEL}.trans.lock"
    
    # Try acquiring transition lock (up to 5 attempts with 0.1s delay)
    ACQUIRED=0
    for i in 1 2 3 4 5; do
        if mkdir "$TRANS_LOCK" 2>/dev/null; then
            ACQUIRED=1
            break
        fi
        sleep 0.1
    done
    if [ "$ACQUIRED" -ne 1 ]; then
        echo "[M11_WATCHDOG] ERROR: Failed to acquire transition lock for disarm." >&2
        exit 1
    fi
    
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ROLLING_BACK" ]; then
        rm -rf "$TRANS_LOCK" 2>/dev/null || true
        echo "[M11_WATCHDOG] ERROR: Cannot disarm: rollback already in progress!" >&2
        exit 1
    fi
    
    echo "DISARMED" > "$STATE_FILE" 2>/dev/null || true
    rm -f "$SENTINEL" 2>/dev/null || true
    
    WD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$WD_PID" ] && kill -0 "$WD_PID" 2>/dev/null; then
        kill -TERM "$WD_PID" 2>/dev/null || true
    fi
    
    rm -rf "$TRANS_LOCK" 2>/dev/null || true
    echo "[M11_WATCHDOG] Disarmed successfully."
    exit 0
fi

# 1. Parameter Count Validation
if [ "$#" -lt 3 ]; then
    echo "[M11_WATCHDOG] ERROR: Missing required arguments. Expected: <TIMEOUT> <SENTINEL_FILE> <ROLLBACK_HELPER> [ARGS...]" >&2
    exit 1
fi

TIMEOUT="$1"
SENTINEL="$2"
ROLLBACK_HELPER="$3"

LOG_TAG="M11_WATCHDOG"
STATE_FILE="${SENTINEL}.state"
LOCK_DIR="${SENTINEL}.lock"
TRANS_LOCK="${SENTINEL}.trans.lock"
ERROR_LOG="${SENTINEL}.error.log"

log_msg() {
    logger -t "$LOG_TAG" "$1" 2>/dev/null || echo "[$LOG_TAG] $1" >&2
}

# 2. Check for Previous Unhandled Failure States
if [ -f "$STATE_FILE" ]; then
    PREV_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    if [ "$PREV_STATE" = "ROLLBACK_FAILED" ] || [ "$PREV_STATE" = "SLEEP_FAILED" ]; then
        log_msg "CRITICAL: Previous watchdog ended in unhandled failure state '$PREV_STATE'. Refusing to start until resolved."
        exit 1
    fi
fi

# 3. Parameter Validation: Ensure TIMEOUT is an integer within 1..86400 seconds
if ! echo "$TIMEOUT" | grep -Eq '^[1-9][0-9]*$' || [ "$TIMEOUT" -gt 86400 ]; then
    log_msg "ERROR: Invalid TIMEOUT parameter: '$TIMEOUT'. Must be an integer between 1 and 86400. Aborting."
    exit 1
fi

# Shift the first 3 parameters so "$@" contains ONLY the rollback arguments
shift 3

# 4. Mutual Exclusion: Atomic Directory Lock
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    EXISTING_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "UNKNOWN")
    log_msg "ERROR: Another watchdog instance is already active for '$SENTINEL' (PID: $EXISTING_PID). Aborting."
    exit 1
fi
echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || true

# 5. Sentinel & State File Initialization
if ! touch "$SENTINEL" 2>/dev/null || ! echo "ARMED" > "$STATE_FILE" 2>/dev/null; then
    log_msg "ERROR: Failed to initialize sentinel or state file at '$SENTINEL'. Aborting."
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    exit 1
fi

# 6. Traps for Signals
trap '' HUP

trap '
    # Acquire transition lock
    ACQ=0
    for i in 1 2 3 4 5; do
        if mkdir "$TRANS_LOCK" 2>/dev/null; then
            ACQ=1
            break
        fi
        sleep 0.05
    done
    
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ "$CURRENT_STATE" = "ARMED" ] || [ "$CURRENT_STATE" = "DISARMED" ]; then
        echo "CANCELLED_BY_SIGNAL" > "$STATE_FILE" 2>/dev/null || true
        log_msg "Watchdog received signal while $CURRENT_STATE. Exiting cleanly without rollback."
        rm -f "$SENTINEL" "$STATE_FILE" 2>/dev/null || true
        rm -rf "$LOCK_DIR" "$TRANS_LOCK" 2>/dev/null || true
        exit 0
    elif [ "$CURRENT_STATE" = "ROLLING_BACK" ]; then
        log_msg "Watchdog received signal during active rollback. Allowing rollback to complete."
        rm -rf "$TRANS_LOCK" 2>/dev/null || true
    fi
' TERM INT

log_msg "Watchdog armed for ${TIMEOUT}s. Sentinel: $SENTINEL. Helper: $ROLLBACK_HELPER"

# 7. Sleep for timeout window with failure detection
if ! sleep "$TIMEOUT"; then
    log_msg "CRITICAL: Sleep command failed or was interrupted unexpectedly. Aborting without rollback to prevent premature reversion."
    mkdir "$TRANS_LOCK" 2>/dev/null || true
    echo "SLEEP_FAILED" > "$STATE_FILE" 2>/dev/null || true
    rm -rf "$LOCK_DIR" "$TRANS_LOCK" 2>/dev/null || true
    exit 1
fi

# 8. Synchronized State Transition using Transition Lock
ACQUIRED=0
for i in 1 2 3 4 5; do
    if mkdir "$TRANS_LOCK" 2>/dev/null; then
        ACQUIRED=1
        break
    fi
    sleep 0.05
done

DO_ROLLBACK=0
if [ "$ACQUIRED" -eq 1 ]; then
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN")
    if [ -f "$SENTINEL" ] && [ "$CURRENT_STATE" = "ARMED" ]; then
        echo "ROLLING_BACK" > "$STATE_FILE" 2>/dev/null || true
        DO_ROLLBACK=1
    fi
    rm -rf "$TRANS_LOCK" 2>/dev/null || true
fi

if [ "$DO_ROLLBACK" -eq 1 ]; then
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

log_msg "Sentinel missing or disarmed prior to timeout. Watchdog exiting cleanly without rollback."
rm -f "$STATE_FILE" 2>/dev/null || true
rm -rf "$LOCK_DIR" 2>/dev/null || true
exit 0
