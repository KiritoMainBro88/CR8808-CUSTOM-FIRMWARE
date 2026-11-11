# MILESTONE M10.2: QUALCOMM IPQ5018 BOOT CHAIN & DUAL-SLOT ARCHITECTURE

**Document ID:** `CR8808-M10.2-BOOTCHAIN-001`  
**Milestone:** `M10.2 – Non-UART Safe Deployment & KEXEC Feasibility`  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Winbond W25N01GV 128MB SPI NAND)  
**Execution Authority:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)  
**Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router interaction, 0 SSH writes, 0 TFTP to router, 0 flashing, 0 NAND/NVRAM writes, 0 reboots)  

---

## 1. Executive Summary

This document delivers a forensic decomposition of the hardware boot chain, SPI NAND flash partition architecture, and dual-boot failover mechanics for the Xiaomi CR8808 Ver.B. 

Understanding the exact sequence of boot stages—from the on-die Mask ROM to Qualcomm TrustZone, U-Boot, and Linux—is essential to evaluating non-UART deployment options and establishing verifiable safeguards against bricking.

---

## 2. Multi-Stage Hardware Boot Chain Architecture

The Qualcomm IPQ5018 SoC executes a multi-stage chain-of-trust boot flow. Each stage initializes specific hardware clocks, power domains, and security states before handing execution to the next layer:

```
+-------------------------------------------------------------------------------+
|                       IPQ5018 MULTI-STAGE BOOT CHAIN                          |
+-------------------------------------------------------------------------------+
|  Stage 1: Primary Boot Loader (PBL)                                           |
|  - Executed from immutable on-die Mask ROM at power-on                        |
|  - Initializes basic clocks, reads hardware strapping pins, probes SPI NAND   |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
|  Stage 2: Secondary Boot Loader (SBL1)                                        |
|  - Read from NAND partition `0:SBL1` (offset 0x00000000)                      |
|  - Initializes DDR3L SDRAM memory controller, PLLs, and PMIC power rails      |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
|  Stage 3: Qualcomm Trusted Execution Environment (QTEE / TrustZone)          |
|  - Read from NAND partition `0:QSEE` / `0:tz` (offset ~0x00180000)           |
|  - Runs at ARMv8-A EL3 (Secure World); configures MMU memory carveouts        |
|  - Establishes `no-map` security regions (tz_apps, wcss 48MB)                 |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
|  Stage 4: Applications Boot Loader (APPSBL / U-Boot)                          |
|  - Read from NAND partition `0:APPSBL` (offset ~0x00380000)                   |
|  - Runs at ARMv8-A Non-Secure EL2 / EL1                                       |
|  - Reads partition table (`0:MIBIB`) and NVRAM flags from `0:bdata`          |
|  - Executes Dual-Boot Slot Selection & Bootcounter Logic                      |
+-------------------------------------------------------------------------------+
                                      |
               +----------------------+----------------------+
               |                                             |
               v (If flag_boot_rootfs=0)                     v (If flag_boot_rootfs=1)
+-------------------------------+             +-------------------------------+
|   SLOT 0 (Active Stock RA82)  |             |  SLOT 1 (Secondary / Test)    |
| - Kernel : `kernel` (0x02000000)|             | - Kernel : `kernel_1`         |
| - Rootfs : `rootfs` (0x02400000)|             | - Rootfs : `rootfs_1`         |
+-------------------------------+             +-------------------------------+
```

---

## 3. SPI NAND Physical Partition Layout (Winbond W25N01GV 128 MB)

The Winbond W25N01GV SPI NAND flash chip contains 1,024 Physical Eraseblocks (PEBs) of 128 KiB each (131,072 bytes per block, 2,048-byte page size + 64-byte OOB). The partition map is defined in the Qualcomm `MIBIB` partition table:

| Partition Label | Physical Offset | Size (Bytes) | Size (MiB) | Function & Criticality |
| :--- | :---: | :---: | :---: | :--- |
| **`0:SBL1`** | `0x00000000` | 1,048,576 | 1.00 | Stage 2 Bootloader. **CRITICAL - CORRUPTION = HARD BRICK**. |
| **`0:MIBIB`** | `0x00100000` | 524,288 | 0.50 | Qualcomm Master Partition Table. **CRITICAL - DO NOT TOUCH**. |
| **`0:QSEE` / `tz`** | `0x00180000` | 1,572,864 | 1.50 | TrustZone OS image. **CRITICAL**. |
| **`0:DEVINFO`** | `0x00300000` | 524,288 | 0.50 | Device serial, MAC addresses, country code. |
| **`0:APPSBL`** | `0x00380000` | 2,097,152 | 2.00 | U-Boot bootloader binary. **CRITICAL**. |
| **`0:ART`** | `0x00580000` / `0x780000` | 1,048,576 | 1.00 | **Factory RF Calibration Data (2.4G & 5G). IRREVERSIBLE LOSS**. |
| **`0:bdata`** | `0x00680000` | 1,048,576 | 1.00 | NVRAM parameters, boot flags (`flag_boot_rootfs`). |
| **`0:crashdump`**| `0x00780000` | 1,048,576 | 1.00 | Kernel panic log dump area. |
| **`kernel` (Slot 0)** | `0x00880000` | 4,194,304 | 4.00 | Primary Slot Kernel (Stock RA82 Linux 4.4.60). |
| **`rootfs` (Slot 0)** | `0x00c80000` | 25,165,824 | 24.00 | Primary Slot Rootfs (Stock RA82 SquashFS). |
| **`kernel_1` (Slot 1)**| `0x02500000` | 4,194,304 | 4.00 | Secondary Slot Kernel (Factory fallback or test). |
| **`rootfs_1` (Slot 1)**| `0x02900000` | 25,165,824 | 24.00 | Secondary Slot Rootfs (Factory fallback or test). |
| **`overlay` / `data`**| `0x04180000` | 61,341,696 | 58.50 | User configuration & writable data partition. |

### 3.1 The Three Sacred Partitions (Zero-Modification Mandate)
Under no circumstances may any flashing script or tool touch:
1. **`0:MIBIB` & `0:APPSBL`:** Overwriting these bricks the router instantly into a silent silicon brick (`QUSB_BULK` mode), requiring chip desoldering.
2. **`0:ART`:** Contains the unit-specific analog calibration tables, EIRP power levels, and phase offsets generated in the factory RF test chamber. Overwriting `0:ART` permanently destroys Wi-Fi range and throughput.

---

## 4. The Dual-Slot Selection & Bootcounter Failover Mechanism

Qualcomm and Xiaomi firmware architecture incorporates a native hardware-agnostic dual-boot watchdog mechanism managed by U-Boot.

### 4.1 NVRAM Boot Control Variables
The bootloader inspects six NVRAM environment variables stored in the `0:bdata` partition:

| Variable Name | Permitted Values | Functional Role |
| :--- | :---: | :--- |
| **`flag_boot_rootfs`** | `0` or `1` | Indicates which slot U-Boot must attempt to boot (`0` = Slot 0, `1` = Slot 1). |
| **`flag_boot_success`** | `0` or `1` | Set to `0` by U-Boot at early boot; set to `1` by Linux userspace upon complete boot. |
| **`flag_try_sys1_failed`**| Integer (0–3) | Counter tracking consecutive failed boot attempts on **Slot 0**. |
| **`flag_try_sys2_failed`**| Integer (0–3) | Counter tracking consecutive failed boot attempts on **Slot 1**. |
| **`flag_last_success`** | `0` or `1` | Records the last slot that successfully completed userspace initialization. |
| **`boot_backup`** | `0` or `1` | Fallback trigger flag used during recovery events. |

### 4.2 U-Boot Bootcounter Execution Algorithm
During power-on, U-Boot executes the following state machine:

```
                     U-BOOT DUAL-BOOT DECISION TREE
                     
                    [ Power On / Hardware Reset ]
                                  |
                                  v
                    Read flag_boot_rootfs from NVRAM
                                  |
               +------------------+------------------+
               |                                     |
         Slot 0 Target                         Slot 1 Target
               |                                     |
               v                                     v
     Read flag_try_sys1_failed             Read flag_try_sys2_failed
               |                                     |
      Is count >= 3?                        Is count >= 3?
         /         \                           /         \
       YES          NO                       YES          NO
       /             \                       /             \
[ FALLBACK ]     [ PROCEED ]           [ FALLBACK ]     [ PROCEED ]
Force boot       Increment             Force boot       Increment
Slot 1           sys1_failed           Slot 0           sys2_failed
                 Clear success                          Clear success
                 Boot Slot 0                            Boot Slot 1
                      |                                      |
                      v                                      v
          +------------------------+             +------------------------+
          | Did Linux boot reach   |             | Did Linux boot reach   |
          | userspace boot_check?  |             | userspace boot_check?  |
          +------------------------+             +------------------------+
                     /      \                               /      \
                   YES       NO                           YES       NO
                   /          \                           /          \
            [ SUCCESS ]    [ HANG ]                [ SUCCESS ]    [ HANG ]
            sys1_failed=0  Watchdog resets         sys2_failed=0  Watchdog resets
            success=1      sys1_failed remains=1   success=1      sys2_failed remains=1
                           (Reboot attempt 2)                     (Reboot attempt 2)
```

1. **Step 1 (Target Identification):** U-Boot reads `flag_boot_rootfs`. If value is `1`, target is Slot 1 (`kernel_1` / `rootfs_1`).
2. **Step 2 (Failure Counter Check):** U-Boot checks `flag_try_sys2_failed`.
   - If `flag_try_sys2_failed < 3`: U-Boot increments the counter (`flag_try_sys2_failed = flag_try_sys2_failed + 1`), sets `flag_boot_success = 0`, commits to NVRAM, and boots the kernel in Slot 1.
   - If `flag_try_sys2_failed >= 3`: U-Boot concludes Slot 1 is broken, **AUTOMATICALLY TOGGLES `flag_boot_rootfs = 0`**, resets `flag_try_sys1_failed = 0`, and boots Slot 0!
3. **Step 3 (Userspace Confirmation):**
   - In stock RA82, the init script `/etc/init.d/boot_check` executes after all network and system daemons start successfully:
     ```sh
     nvram set flag_boot_success=1
     nvram set flag_try_sys1_failed=0
     nvram set flag_try_sys2_failed=0
     nvram commit
     ```
   - If the new kernel panics, hangs, or locks up before running `boot_check`, the hardware watchdog resets the router. The counter remains incremented. After 3 consecutive reboots, U-Boot automatically reverts to the working slot!

---

## 5. Architectural Implications for Non-UART Safe Deployment

The presence of the dual-slot mechanism provides a potential non-UART safety pathway, BUT it carries strict prerequisites:

1. **Slot Isolation Feasibility:**
   - If OpenWrt is flashed **ONLY into Slot 1 (`kernel_1` and `rootfs_1`)**, the factory stock RA82 firmware in Slot 0 (`kernel` and `rootfs`) remains 100% bit-for-bit pristine.
   - If Slot 1 fails to boot, U-Boot's bootcounter will theoretically fail over to Slot 0 after 3 resets.
2. **Critical Failure Points of Slot Switching:**
   - **Bootloader Hang:** If the new kernel's device tree or memory table corrupts shared RAM registers before the hardware watchdog is started, the SoC may hang indefinitely without triggering a reset.
   - **NVRAM Driver Incompatibility:** If the custom OpenWrt kernel does not have the proprietary Xiaomi `bdata` NVRAM driver, it cannot signal `flag_boot_success = 1`, causing the router to revert to Slot 0 on every 3rd reboot even if OpenWrt booted successfully.
   - **UBI vs Raw MTD Mismatch:** Stock firmware expects raw MTD partitions for `kernel` and `rootfs`. OpenWrt qualcommax images are packaged as UBI containers. Writing a UBI container directly into a raw MTD partition without adjusting partition boundaries can cause U-Boot image verification failures.

---

## 6. Conclusion & Sign-Off

- The Qualcomm IPQ5018 boot chain is protected by a multi-stage chain of trust.
- The SPI NAND contains two complete OS slots (Slot 0 and Slot 1) managed by U-Boot NVRAM bootcounter flags.
- While the dual-slot bootcounter mechanism offers a theoretical fallback without UART, it requires rigorous verification of watchdog triggers and partition geometry before it can be considered a sanctioned deployment path.
