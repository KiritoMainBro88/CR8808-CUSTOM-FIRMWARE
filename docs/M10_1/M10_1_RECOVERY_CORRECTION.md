# MILESTONE M10.1: RECOVERY MECHANISM DISAMBIGUATION & SAFETY AUDIT

**Document ID:** `CR8808-M10.1-REC-001`  
**Milestone:** `M10.1 – Evidence Correction & Architecture Review`  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Winbond W25N01GV 128MB SPI NAND)  
**Execution Authority:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)  
**Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router interaction, 0 SSH, 0 TFTP to router, 0 flashing, 0 NAND/NVRAM writes, 0 reboots)  

---

## 1. Executive Summary

This document addresses the critical technical clarification requested by the Chief Architect regarding recovery mechanisms for the Xiaomi CR8808 Ver.B. 

Specifically, this audit formally disambiguates between **TFTP Firmware Restoration (NAND Flashing)** and **Pure TFTP RAM Boot (`bootm`)**, resolves the requirement for UART interaction, details catastrophic hard-brick failure modes, and reaffirms the strict enforcement of the **`NO-GO FLASH`** safety boundary.

---

## 2. Disambiguation of Recovery Mechanisms

Early project documentation conflated two fundamentally different recovery mechanisms under the broad term "TFTP Recovery". We now explicitly delineate these paths:

```
+---------------------------------------------------------------------------------------+
|                             CR8808 RECOVERY TAXONOMY                                  |
+-------------------------------------------+-------------------------------------------+
|      NON-UART RECOVERY PATHWAYS           |         UART-INTERACTIVE PATHWAYS         |
|         (WRITES TO NAND FLASH)            |           (PURE ZERO-RISK RAM)            |
+---------------------+---------------------+-------------------------------------------+
|  Xiaomi MiWiFi      |  U-Boot Web         |  U-Boot Interactive Console               |
|  Repair Tool (TFTP) |  Failsafe (HTTP)    |  (`tftpboot` + `bootm`)                   |
+---------------------+---------------------+-------------------------------------------+
| - Auto-pulls image  | - Web UI @          | - Requires physical serial cable          |
|   from 192.168.31.x |   192.168.31.1      | - Interrupts autoboot at prompt           |
| - WRITES TO NAND    | - WRITES TO NAND    | - Loads FIT image directly into RAM       |
| - High Risk of      | - High Risk of      | - ZERO NAND WRITES                        |
|   Bricking          |   Bricking          | - ZERO BRICKING RISK                      |
+---------------------+---------------------+-------------------------------------------+
```

### 2.1 Mechanism 1: Xiaomi MiWiFi TFTP Repair Tool (Non-UART, NAND Write)
- **Operation:** When the router powers on with the Reset button held down, or detects corrupted boot headers in primary kernel partitions, stock Xiaomi U-Boot executes an emergency recovery routine:
  - Configures Ethernet PHY to `192.168.31.1`.
  - Sends UDP broadcast TFTP requests searching for a server at `192.168.31.100`.
  - Downloads the firmware binary (`firmware.bin` or `test.bin`).
- **CRITICAL HARDWARE REALITY:**  
  Once downloaded into RAM buffers, the stock bootloader **AUTOMATICALLY ERASES AND WRITES TO NAND FLASH** (specifically writing to MTD partitions `kernel`, `rootfs`, or `ubi`).
- **Risk Profile:** **HIGH RISK**. If the flashed image has an invalid UBI layout, broken switch driver, or early kernel panic, the flash memory is corrupted. The device will reboot into a broken system, potentially rendering the non-UART recovery routine inoperable.

### 2.2 Mechanism 2: U-Boot Web Failsafe (Non-UART, NAND Write)
- **Operation:** Some intermediate community U-Boot builds provide an embedded HTTP server (e.g. at `192.168.31.1`) allowing users to upload firmware via a web browser.
- **CRITICAL HARDWARE REALITY:**  
  The Web Failsafe interface also **WRITES DIRECTLY TO NAND FLASH**. It is a flashing mechanism, not a memory-only test harness.
- **Risk Profile:** **HIGH RISK**. Identical failure modes to Mechanism 1.

### 2.3 Mechanism 3: Pure TFTP RAM Boot (`bootm`) (REQUIRES UART INTERACTION)
- **Operation:** The developer connects a 3.3V USB-to-UART TTL serial adapter to the physical RX, TX, and GND pins on the CR8808 PCB (115200 8N1).
  - During early power-on, the autoboot prompt is interrupted: `Hit any key to stop autoboot: 0`.
  - The developer manually executes:
    ```text
    setenv ipaddr 192.168.31.1
    setenv serverip 192.168.31.100
    tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-xiaomi_cr8818-initramfs-uImage.itb
    bootm 0x44000000#config@mp03.3
    ```
  - The U-Boot command `bootm` verifies the FIT container, unpacks the ARM64 kernel and rootfs directly into DDR3L SDRAM, and branches execution to `0x41000000`.
- **CRITICAL HARDWARE REALITY:**  
  **ZERO BYTES ARE WRITTEN TO NAND FLASH.** If the kernel crashes or panics, a simple power cycle restores the router to its 100% original, untouched stock factory firmware.
- **The Core Constraint:**  
  **Stock Xiaomi U-Boot DOES NOT offer an automated fallback to pure RAM boot without UART interaction.** An automated non-UART boot requires flashing a customized bootloader, which itself carries catastrophic bricking risk.

---

## 3. Catastrophic Hard-Brick Failure Modes

Flashing unverified firmware to SPI NAND without an established UART console introduces several catastrophic failure modes:

| Failure Mode | Mechanism | Consequence | Recovery Method |
| :--- | :--- | :--- | :--- |
| **Early Kernel Panic / Watchdog Loop** | Kernel crashes before initializing watchdog driver or feeding SoC hardware timer. | Hardware watchdog resets IPQ5018 every 30 seconds -> Infinite reboot loop. | Must intercept via UART or force flash via MiWiFi Tool. |
| **`0:art` Partition Overwrite** | Malformed UBI partition table or incorrect MTD offset causes flash write to spill into ART partition (`0x700000`). | Factory RF calibration data, power tables, and MAC addresses are permanently destroyed. | **PERMANENT DAMAGE**. Cannot be recovered without factory calibration dump from identical board. |
| **Corrupted Bootloader (`SBL` / `MIBIB`)** | Attempting to flash full image containing incompatible bootloader blocks. | Device fails power-on self-test; completely silent serial console; no LEDs. | **HARD BRICK**. Requires desoldering Winbond SPI NAND chip or Qualcomm Emergency Download (`QUSB_BULK`). |
| **Switch Deadlock on Boot** | Switch driver fails to probe (`0xffffffff` PLL race condition); all physical Ethernet ports dead. | Device boots, but Ethernet switch is tri-stated; no DHCP, no IP, no web GUI, no TFTP response. | Device appears dead to network. Requires UART console to diagnose and recover. |

---

## 4. Reaffirmation of Safety Boundaries: NO-GO FLASH

Because:
1. No automated non-UART pure RAM boot exists on stock U-Boot.
2. All non-UART recovery methods perform irreversible writes to physical NAND flash.
3. Unverified flashing risks bricking the router and destroying factory calibration data.

The Lead Developer and Research Engineering team formally ratify and enforce the following safety rules:

> [!CAUTION]
> ### STRICT NO-GO FLASH ENFORCEMENT
> - **Flash Authorization:** **DENIED / STRICT NO-GO FLASH**.
> - **Router Interaction:** **0 SSH, 0 Telnet, 0 TFTP transmission, 0 HTTP flashing, 0 NAND/NVRAM writes, 0 reboots.**
> - **Artifact Classification:** All generated images in `artifacts/m10_images/` (`factory.ubi`, `sysupgrade.bin`, `initramfs-uImage.itb`) remain strictly classified as **`PC_SIDE_AUDIT_ARTIFACTS`**.
> - **Lab Directory Integrity:** `D:\vibecode\test_wifi` remains 100% untouched.
> - **Pre-Requisite for Milestone M11:** Physical testing under Milestone M11 SHALL ONLY BE AUTHORIZED once UART serial console access is physically attached and verified, or under an explicit Chief Architect directive.

---

## 5. Evidence Classification & Taxonomy Compliance

| Assertion / Analysis | Evidence Tier | Primary Verification Reference |
| :--- | :---: | :--- |
| MiWiFi Tool writes directly to NAND | `SOURCE_VERIFIED` | Xiaomi stock U-Boot GPL source code `cmd_bootm.c` / `ipq5018_nand.c` |
| U-Boot `bootm` pure RAM boot zero NAND write | `SOURCE_VERIFIED` | U-Boot upstream architecture & FIT specification |
| Stock U-Boot non-UART RAM boot unavailability | `DEVICE_READBACK_RECONCILED` | Verified against CR8808/CR8818 bootloader environment logs |
| Permanent loss risk on `0:art` overwrite | `SOURCE_VERIFIED` | NAND MTD geometry audit (`docs/M9/M9_UBI_GEOMETRY_REPORT.md`) |
| Safety Gate Enforcement (`NO-GO FLASH`) | `STATIC_VERIFIED` | Zero network sockets open to 192.168.31.1; 0 router packets sent |

---

## 6. Conclusion & Sign-Off

The recovery mechanism boundaries are clear and indisputable:
- Non-UART recovery paths are **NAND-writing restoration tools**, not memory-only test mechanisms.
- Pure RAM testing requires UART serial interaction.
- The **`NO-GO FLASH`** mandate remains absolute and unbreached.
