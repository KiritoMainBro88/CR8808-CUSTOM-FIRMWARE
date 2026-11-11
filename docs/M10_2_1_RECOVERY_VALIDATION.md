# MILESTONE M10.2.1: NON-UART RECOVERY VALIDATION & COMMUNITY METHOD AUDIT

**Document ID:** `CR8808-M10.2.1-RECOVERY-001`  
**Milestone:** `M10.2.1 – Critical Evidence Correction & Non-UART Recovery Validation`  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Winbond W25N01GV 128MB SPI NAND)  
**Execution Authority:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)  
**Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router writes, 0 flashing, 0 NAND/NVRAM modifications, 0 reboots)  
**Evidence Grounding:** Empirical analysis of live device readback, Qualcomm boot architecture, and community deployment code

---

## 1. Executive Summary & Audit Purpose

This document provides a rigorous, skeptical re-evaluation of non-UART firmware deployment and recovery mechanisms on the Xiaomi CR8808 Ver.B router.

In Milestone M10.2, several critical assumptions were asserted as verified facts:
1. That Qualcomm hardware watchdog automatically reboots the router after 30 seconds if a custom kernel hangs.
2. That stock U-Boot automatically reverts to the alternate slot after 3 failed boot attempts (`flag_try_sysX_failed >= 3`).
3. That the official Xiaomi MiWiFi Repair Tool provides a guaranteed, fail-safe recovery path for the CR8808 Ver.B.

Under the Chief Architect's directive, this document **retracts premature verification claims**, reclassifies unproven recovery mechanics to `UNVERIFIED_ON_CR8818` / `THEORETICAL_HAZARD`, and conducts an in-depth forensic dissection of the community deployment pattern popularized by `IITII/openwrt-redmi-ax3000`.

---

## 2. Reclassification of Recovery Mechanisms

To uphold scientific integrity and absolute hardware preservation, the recovery capabilities of the CR8808 Ver.B are formally categorized below:

```
+---------------------------------------------------------------------------------------------------------+
|                                    RECOVERY MECHANISM AUDIT MATRIX                                      |
+--------------------------+-----------------------+--------------------------+---------------------------+
| Mechanism                | M10.2 Classification  | M10.2.1 Reclassification | Forensic Technical Reason |
+--------------------------+-----------------------+--------------------------+---------------------------+
| Hardware Watchdog        | VERIFIED              | **THEORETICAL_HAZARD**   | Early kernel hangs before |
| Auto-Reset (30s)         |                       | **UNVERIFIED_ON_CR8818** | WDT init freeze CPU with  |
|                          |                       |                          | WDT disabled by U-Boot.   |
+--------------------------+-----------------------+--------------------------+---------------------------+
| U-Boot Bootcounter       | VERIFIED              | **THEORETICAL_HAZARD**   | No empirical proof that   |
| Failover (3 Retries)     |                       | **UNVERIFIED_ON_CR8818** | CR8818 carrier U-Boot     |
|                          |                       |                          | auto-toggles boot flags.  |
+--------------------------+-----------------------+--------------------------+---------------------------+
| Xiaomi MiWiFi            | OFFICIALLY VERIFIED   | **THEORETICAL_HAZARD**   | Carrier model mismatch    |
| TFTP Repair Tool         |                       | **UNVERIFIED_ON_CR8818** | (CR8818 vs RA82); risks   |
|                          |                       |                          | full NAND reflash/brick.  |
+--------------------------+-----------------------+--------------------------+---------------------------+
| Inactive Slot Isolation  | SOUND                 | **VALIDATED IN PRINCIPLE**| Physically preserves live |
| (Deploy Slot 0 only)     | (With slot inversion) | **(SLOT 0 TARGET ONLY)** | Slot 1 intact; requires   |
|                          |                       |                          | exact ubiformat payload.  |
+--------------------------+-----------------------+--------------------------+---------------------------+
```

---

## 3. Forensic Analysis of `IITII/openwrt-redmi-ax3000` Deployment Pattern

The repository `IITII/openwrt-redmi-ax3000` documents a community method for flashing OpenWrt to Xiaomi IPQ50xx routers via an active SSH root shell without opening the chassis.

### 3.1 Script Execution Logic & Slot Detection
The community installation script performs dynamic slot detection by querying `/proc/cmdline`:

```sh
# Community Slot Detection Logic:
CURRENT_SLOT=$(grep -o 'ubi.mtd=rootfs_[0-9]' /proc/cmdline || grep -o 'ubi.mtd=rootfs' /proc/cmdline)

if [ "$CURRENT_SLOT" = "ubi.mtd=rootfs_1" ]; then
    TARGET_MTD="/dev/mtd18"      # Slot 0 physical partition
    TARGET_FLAG="0"              # Next boot target: Slot 0
elif [ "$CURRENT_SLOT" = "ubi.mtd=rootfs" ]; then
    TARGET_MTD="/dev/mtd19"      # Slot 1 physical partition
    TARGET_FLAG="1"              # Next boot target: Slot 1
else
    echo "ERROR: Unable to identify active rootfs slot!"
    exit 1
fi
```

### 3.2 The Flashing & NVRAM Toggling Procedure
Once the inactive slot is determined, the community method executes:

```sh
# 1. Format the inactive partition and write OpenWrt factory UBI image:
ubiformat ${TARGET_MTD} -y -f /tmp/openwrt-factory.ubi

# 2. Configure NVRAM to switch boot slot on next startup:
nvram set flag_boot_rootfs=${TARGET_FLAG}
nvram set flag_last_success=${TARGET_FLAG}
nvram set flag_boot_success=0
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram commit

# 3. Reboot into the new firmware:
reboot
```

### 3.3 Critical Technical Analysis for Xiaomi CR8808 Ver.B

While the **dual-slot targeting logic** of the IITII script is structurally sound, blindly adopting this script or its precompiled images on the CR8808 Ver.B carries **catastrophic risks**:

#### Fatal Hazard 1: Binary & Hardware Incompatibility
- `IITII/openwrt-redmi-ax3000` is built for the **Redmi AX3000** (Board Profile `ap-mp03.1`), which uses Qualcomm's internal Ethernet switch / QCA8337.
- Our device is the **Xiaomi CR8808 Ver.B** (Board Profile `ap-mp03.3`, Internal Codename `CR8818`), which uses the **Motorcomm YT9215SC switch at MDIO `0x1d`**.
- **Consequence:** Flashing an AX3000 image onto CR8808 Ver.B boots a kernel that probes MDIO `0x17` for a Qualcomm switch, fails to find it, and initializes **zero Ethernet ports**. The router becomes completely unreachable over LAN.

#### Fatal Hazard 2: Kernel & Toolchain Generation Drift
- The IITII repository relies on Qualcomm QSDK Linux 5.4 or early OpenWrt snapshot trees.
- It lacks the modern Linux 6.12 backported Motorcomm DSA driver, the `tag_yt921x` switch tagger, and modern BoringTun Rust userspace components.
- Direct usage of community AX3000 payloads is strictly prohibited.

#### Validated Architectural Principle:
The *methodology* of:
1. Dynamically inspecting `/proc/cmdline` to ensure we are running on `rootfs_1`.
2. Targeting strictly the inactive physical container `/dev/mtd18` (`rootfs`).
3. Using `ubiformat /dev/mtd18 -y -f <image.ubi>` to correctly lay down UBI Erase Counter (EC) and Volume Identifier (VID) headers.
4. Setting NVRAM `flag_boot_rootfs=0`.

is technically valid **ONLY when the flashed payload is our verified CR8818 OpenWrt 25.12.6 image**, and **ONLY after the fallback mechanisms have been objectively characterized**.

---

## 4. Forensic Audit of U-Boot Bootcounter Failover

### 4.1 Theoretical Mechanism
In Qualcomm IPQ50xx reference designs:
1. U-Boot reads `flag_boot_rootfs` from `bdata` (offset `0x00900000`).
2. If `flag_boot_rootfs == 0`, U-Boot checks `flag_try_sys1_failed`. If `flag_boot_rootfs == 1`, it checks `flag_try_sys2_failed`.
3. If the failure counter exceeds a defined threshold (typically 3):
   ```text
   if (flag_try_sys1_failed >= 3) {
       printf("Slot 0 boot failed 3 times! Falling back to Slot 1\n");
       setenv("flag_boot_rootfs", "1");
       saveenv();
   }
   ```
4. When Linux boots successfully, a userspace init script (`boot_check` or `/etc/init.d/done`) executes:
   ```sh
   nvram set flag_boot_success=1
   nvram set flag_try_sys1_failed=0
   nvram commit
   ```

### 4.2 Why Bootcounter Failover is NOT a Guaranteed Safety Net on CR8818:

#### Failure Mode A: The Early Kernel Hang & Watchdog Void
- Stock U-Boot enables a hardware watchdog timer while U-Boot is running.
- Prior to executing `bootm` (jumping into the Linux kernel entry point at physical DRAM `0x41000000`), U-Boot **frequently disables or pets the hardware watchdog** to prevent a reset during kernel decompression.
- If the new Linux 6.12 kernel hangs during early boot (e.g. in `arch/arm64/kernel/head.S`, early device tree parsing, or before `ipq5018-wdt` driver probes):
  - The watchdog timer is NOT ticking.
  - The CPU core sits in an infinite spin loop or low-power `wfi`.
  - The router will hang forever with solid LEDs. It will **NEVER auto-reset**.
- Without an auto-reset, the system cannot trigger another boot attempt.

#### Failure Mode B: Failure Counter Persistence on Manual Power Cycle
- If the router hangs and the user pulls the power plug:
  - Did U-Boot increment `flag_try_sys1_failed` *before* jumping to the kernel, or does it only increment it *after* detecting a bad image CRC?
  - In many Xiaomi U-Boot implementations, U-Boot only increments `flag_try_sysX_failed` if the kernel image fails U-Boot's FIT/uImage header check. If the kernel loads cleanly into RAM and crashes 5 seconds into boot, **U-Boot never sees the crash**.
  - On subsequent power-on, U-Boot sees `flag_boot_rootfs=0`, boots the broken kernel again, hangs again, and repeats indefinitely.
- **Empirical Status:** We have zero UART logs from CR8808 Ver.B demonstrating that U-Boot increments `flag_try_sys1_failed` across power cuts when a kernel crashes in early userspace.
- **Conclusion:** Bootcounter failover must be treated as `THEORETICAL_HAZARD / UNVERIFIED`.

---

## 5. Forensic Audit of Xiaomi Official MiWiFi Repair Tool

### 5.1 Operating Principle
The Xiaomi MiWiFi Repair Tool (`Xiaoqiang_recovery.exe`):
1. Configures the host PC NIC to static IP `192.168.31.100` / `255.255.255.0`.
2. Runs an integrated TFTP server on UDP port 69 serving official Xiaomi ROM files.
3. The user holds the router's rear **Reset button** for 10–15 seconds while powering on.
4. Stock U-Boot detects the held GPIO reset button, enters an emergency recovery loop, configures its internal GMAC to `192.168.31.1`, and sends TFTP read requests (RRQ) for `test.bin` or `miwifi.bin`.
5. Upon download, U-Boot writes the payload to flash and reboots.

### 5.2 Critical Risks for Xiaomi CR8808 Ver.B:

#### Risk 1: Carrier Hardware ID & Header Rejection
- CR8808 Ver.B is a China Mobile customized product (`model=CR8818`, `ap-mp03.3`).
- The official MiWiFi Repair Tool firmware packages are signed and formatted for retail models (e.g. `RA82`, `AX3000`).
- If U-Boot checks the board header or model string before flashing, it will **reject the retail ROM image**, leaving the router in a failed recovery state.

#### Risk 2: Full Flash Overwrite & Total Erasure
- The official repair tool is NOT a slot-aware recovery mechanism. It is a full factory restorer.
- In many models, the recovery script formats both `rootfs` (Slot 0) and `rootfs_1` (Slot 1), completely obliterating the untouched stock RA82 firmware on Slot 1.
- If the flashed recovery image lacks the Motorcomm YT9215SC switch driver, the router will be permanently soft-bricked without working Ethernet.

#### Risk 3: Windows Firewall & Network Adapter Timing
- TFTP recovery on Windows is notoriously fragile: Windows Firewall routinely blocks UDP port 69 from unrecognized subnets.
- Gigabit NIC auto-negotiation delay (3–5 seconds) often causes the PC to link up *after* U-Boot's TFTP timeout window has expired.
- **Conclusion:** Relying on the MiWiFi Repair Tool as a safety net is premature. It is classified as `THEORETICAL_HAZARD / UNVERIFIED`.

---

## 6. Safe Path Forward: The 4 Pre-Flight Security Gates

Before any write operations to the physical router are ever considered, the following four gates must be satisfied:

```
+----------------------------------------------------------------------------------------------------+
|                                  M10.2.1 PRE-FLIGHT SECURITY GATES                                 |
+--------+------------------------------------+------------------------------------------------------+
| Gate   | Requirement                        | Verification Criterion                               |
+--------+------------------------------------+------------------------------------------------------+
| Gate 1 | Non-Destructive Backup of Sacred   | Full binary dump of `0:ART` (`mtd13`) and `bdata`    |
|        | Partitions to Workstation PC       | (`mtd15`) transferred via SSH/SCP and verified.      |
+--------+------------------------------------+------------------------------------------------------+
| Gate 2 | OpenWrt Inactive Slot Payload      | Custom OpenWrt 25.12.6 UBI image built strictly for  |
|        | Validation                         | CR8818 with YT9215SC DSA, ath11k, and watchdog.     |
+--------+------------------------------------+------------------------------------------------------+
| Gate 3 | Watchdog & Failsafe Network Daemons| Image must include active hardware watchdog keep-    |
|        | Verification in Kernel             | alive and static failsafe IP configuration.          |
+--------+------------------------------------+------------------------------------------------------+
| Gate 4 | Formal Chief Architect Sign-Off    | Explicit written authorization from ChatGPT Chief    |
|        |                                    | Architect prior to executing any flash command.      |
+--------+------------------------------------+------------------------------------------------------+
```

---

## 7. Definitive Verdict

1. **IITII Method:** Valid in its dynamic slot detection and `ubiformat` targeting of inactive Slot 0 (`mtd18`), but its precompiled firmware cannot be used on CR8808 Ver.B.
2. **Bootcounter Failover:** Cannot be assumed to protect against early kernel hangs.
3. **MiWiFi Repair Tool:** Unverified on carrier CR8818 hardware and carries full-flash erasure risk.
4. **Safety Status:** **STRICT NO-GO FLASH REMAINS IN FULL FORCE.**
