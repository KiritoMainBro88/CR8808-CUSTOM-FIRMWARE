#!/bin/sh
# scripts/watchdog_service.sh
# Hardened Reversible Watchdog for M11.1 Runtime Firewall Trials
# Xiaomi CR8808 Ver.B (RA82 v1.4.31 / Linux 4.4.60 QSDK)
#
# Usage:
#   watchdog_service.sh <TIMEOUT_SECONDS> <SENTINEL_FILE> <ROLLBACK_COMMAND_STRING>
#
# Double-Barrier Design:
#   Barrier 1: Sentinel token file. If deleted prior to timeout, rollback is suppressed.
#   Barrier 2: Process signal trapping (SIGHUP ignored; SIGTERM cleanly terminates).

TIMEOUT="${1:-180}"
SENTINEL="${2:-/tmp/m11_watchdog.armed}"
ROLLBACK_CMD="${3:-}"
LOG_TAG="M11_WATCHDOG"

# 1. Immune to SIGHUP (SSH disconnection / session hangup)
trap '' HUP

# 2. Clean termination on SIGTERM or SIGINT (disarm signal)
trap 'logger -t "$LOG_TAG" "Watchdog received termination signal; exiting without action." 2>/dev/null; exit 0' TERM INT

logger -t "$LOG_TAG" "Watchdog armed for ${TIMEOUT}s. Sentinel: $SENTINEL" 2>/dev/null || true

# 3. Sleep for the specified duration
sleep "$TIMEOUT"

# 4. Check if sentinel file still exists (Barrier 1)
if [ -f "$SENTINEL" ]; then
    logger -t "$LOG_TAG" "Timeout expired with active sentinel. Executing rollback..." 2>/dev/null || true
    
    # Execute rollback commands if supplied
    if [ -n "$ROLLBACK_CMD" ]; then
        # Evaluate rollback defensively; ensure execution continues across failures
        eval "$ROLLBACK_CMD"
    fi
    
    # Clean up sentinel after rollback
    rm -f "$SENTINEL" 2>/dev/null || true
    logger -t "$LOG_TAG" "Rollback execution finished." 2>/dev/null || true
else
    logger -t "$LOG_TAG" "Sentinel missing at timeout expiry; trial was cleanly disarmed. Zero action taken." 2>/dev/null || true
fi

exit 0
