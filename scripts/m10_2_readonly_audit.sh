#!/bin/sh
# ==============================================================================
# SCRIPT: m10_2_readonly_audit.sh
# PURPOSE: Class R0 Read-Only Hardware & System Architecture Audit for Xiaomi CR8808/CR8818
# TARGET FIRMWARE: Xiaomi Stock RA82 Global v1.4.31 (Linux 4.4.60 QSDK)
# SAFETY LEVEL: STRICT READ-ONLY (0 writes, 0 mutations, 0 reboots, 0 service restarts)
# ==============================================================================

set -u

OUT_DIR="/tmp/m10_2_audit_$(date +%s 2>/dev/null || echo '001')"
mkdir -p "$OUT_DIR" 2>/dev/null || OUT_DIR="/tmp"

LOG="$OUT_DIR/cr8818_readonly_audit.log"
exec > "$LOG" 2>&1

echo "=============================================================================="
echo "MILESTONE M10.2: CLASS R0 READ-ONLY SYSTEM & KEXEC CAPABILITY AUDIT"
echo "TIMESTAMP: $(date 2>/dev/null || echo 'N/A')"
echo "=============================================================================="

# 1. OS & Kernel Baseline
echo "--- 1. OS & KERNEL IDENTIFICATION ---"
echo "[uname -a]"
uname -a 2>&1 || echo "uname failed"

echo "[cat /proc/version]"
[ -f /proc/version ] && cat /proc/version || echo "/proc/version missing"

# 2. CPU & Architectural Execution State (ARM32 vs ARM64)
echo "--- 2. CPU & ARCHITECTURE AUDIT ---"
echo "[cat /proc/cpuinfo]"
[ -f /proc/cpuinfo ] && cat /proc/cpuinfo || echo "/proc/cpuinfo missing"

# 3. Kernel Configuration & KEXEC Syscall Check
echo "--- 3. KEXEC & KERNEL SYSCALL CAPABILITY ---"
echo "[Checking /proc/config.gz]"
if [ -f /proc/config.gz ]; then
    echo "Found /proc/config.gz; scanning for KEXEC..."
    zcat /proc/config.gz 2>/dev/null | grep -i "KEXEC" || echo "No KEXEC strings in /proc/config.gz"
else
    echo "/proc/config.gz NOT PRESENT in stock kernel"
fi

echo "[Checking /sys/kernel/kexec_loaded]"
if [ -e /sys/kernel/kexec_loaded ]; then
    echo "/sys/kernel/kexec_loaded EXISTS: $(cat /sys/kernel/kexec_loaded 2>/dev/null)"
else
    echo "/sys/kernel/kexec_loaded DOES NOT EXIST (kexec subsystem inactive or uncompiled)"
fi

echo "[Checking /sys/kernel/kexec_crash_loaded]"
if [ -e /sys/kernel/kexec_crash_loaded ]; then
    echo "/sys/kernel/kexec_crash_loaded EXISTS: $(cat /sys/kernel/kexec_crash_loaded 2>/dev/null)"
else
    echo "/sys/kernel/kexec_crash_loaded DOES NOT EXIST"
fi

# 4. RAM Budget & Memory Fragmentation
echo "--- 4. RAM & MEMORY FRAGMENTATION AUDIT ---"
echo "[cat /proc/meminfo]"
[ -f /proc/meminfo ] && cat /proc/meminfo || echo "/proc/meminfo missing"

echo "[cat /proc/buddyinfo]"
[ -f /proc/buddyinfo ] && cat /proc/buddyinfo || echo "/proc/buddyinfo missing"

# 5. MTD Flash Partition Table (Dual-Boot & Calibration Layout)
echo "--- 5. MTD PARTITION LAYOUT ---"
echo "[cat /proc/mtd]"
[ -f /proc/mtd ] && cat /proc/mtd || echo "/proc/mtd missing"

# 6. Bootloader Environment & Failover Flags
echo "--- 6. BOOTLOADER NVRAM & FAILOVER FLAGS ---"
if command -v nvram >/dev/null 2>&1; then
    echo "[nvram get model]: $(nvram get model 2>/dev/null)"
    echo "[nvram get board_id]: $(nvram get board_id 2>/dev/null)"
    echo "[nvram get flag_boot_rootfs]: $(nvram get flag_boot_rootfs 2>/dev/null)"
    echo "[nvram get flag_boot_success]: $(nvram get flag_boot_success 2>/dev/null)"
    echo "[nvram get flag_try_sys1_failed]: $(nvram get flag_try_sys1_failed 2>/dev/null)"
    echo "[nvram get flag_try_sys2_failed]: $(nvram get flag_try_sys2_failed 2>/dev/null)"
    echo "[nvram get boot_backup]: $(nvram get boot_backup 2>/dev/null)"
else
    echo "nvram utility not found in PATH"
fi

# 7. Hardware Peripherals & Modules (Motorcomm Switch & WCSS Wi-Fi)
echo "--- 7. ACTIVE KERNEL MODULES & HARDWARE ---"
echo "[lsmod]"
command -v lsmod >/dev/null 2>&1 && lsmod || echo "lsmod not available"

echo "[dmesg switch search]"
command -v dmesg >/dev/null 2>&1 && dmesg | grep -i -E "yt9215|motorcomm|switch|phy|ath11k|wcss|q6" | tail -n 40 || echo "dmesg empty"

echo "=============================================================================="
echo "AUDIT COMPLETE. OUTPUT CAPTURED TO: $LOG"
echo "ZERO MUTATIONS EXECUTED. SYSTEM STATE 100% UNCHANGED."
echo "=============================================================================="
