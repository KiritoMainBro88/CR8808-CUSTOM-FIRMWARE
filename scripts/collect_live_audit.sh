#!/bin/bash
# Read-only audit script executed from PC via SSH to router
# Usage: ROUTER_PASS="<password>" ./scripts/collect_live_audit.sh

ROUTER_IP="${ROUTER_IP:-192.168.31.1}"
ROUTER_PORT="${ROUTER_PORT:-56789}"
ROUTER_USER="${ROUTER_USER:-root}"

if [ -z "$ROUTER_PASS" ]; then
    echo "ERROR: ROUTER_PASS environment variable is required."
    echo "Example: ROUTER_PASS='mysecret' $0"
    exit 1
fi

sshpass -p "$ROUTER_PASS" ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  "${ROUTER_USER}@${ROUTER_IP}" '
echo "=== UNAME ==="
uname -a
uname -m

echo "=== PROC VERSION ==="
cat /proc/version

echo "=== PROC CMDLINE ==="
cat /proc/cmdline

echo "=== PROC MTD ==="
cat /proc/mtd

echo "=== PROC MEMINFO ==="
cat /proc/meminfo

echo "=== NVRAM FLAGS ==="
echo "model: $(nvram get model)"
echo "board_id: $(nvram get board_id)"
echo "flag_boot_rootfs: $(nvram get flag_boot_rootfs)"
echo "flag_last_success: $(nvram get flag_last_success)"
echo "flag_boot_success: $(nvram get flag_boot_success)"
echo "flag_try_sys1_failed: $(nvram get flag_try_sys1_failed)"
echo "flag_try_sys2_failed: $(nvram get flag_try_sys2_failed)"
echo "boot_backup: $(nvram get boot_backup)"

echo "=== CONFIG_GZ AND KEXEC ==="
if [ -e /proc/config.gz ]; then
    zcat /proc/config.gz | grep -E "(KEXEC|CONFIG_ARM|WATCHDOG)"
else
    echo "/proc/config.gz not present"
fi
ls -la /sys/kernel/kexec* 2>&1

echo "=== WATCHDOG DEVICE AND DMESG ==="
ls -la /dev/watchdog* 2>&1
dmesg | grep -i -E "(watchdog|wdt|boot|rootfs|ubi|partition)" | tail -n 60
' > /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/reports/live_device_audit_m10_2_1.txt
