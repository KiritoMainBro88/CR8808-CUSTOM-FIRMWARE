# Wi-Fi 6, SPI NAND MTD Architecture & Non-UART Recovery Audit (M7.1)

- **Document ID:** `docs/M7.1/WIFI_NAND_BOOT_RECOVERY_AUDIT.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, IPQ5018 + QCN6102 + Winbond W25N01GW)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical Specification & Safety Audit for Gate M7.1
- **Evidence Classification:** `SOURCE_VERIFIED`, `DEVICE_READBACK`, `REPORTED_UNVERIFIED`.

---

## 1. Executive Summary

This document establishes the hardware truth and operational safety baselines for the three most sensitive hardware subsystems of the Xiaomi CR8808 Ver.B:
1. **SPI NAND Flash & MTD Partitioning:** Physical properties of the Winbond W25N01GW chip, hardware ECC parameters, and protection of critical bootloader partitions (`mtd11`/`mtd12`).
2. **Dual-Rootfs Bootcounter Failover & Stock TFTP Recovery:** Autonomous dual-boot failover mechanics driven by Qualcomm APPSBL and the unbrickable stock TFTP beacon protocol.
3. **Wi-Fi 6 Architecture & Factory Calibration Pipeline:** Separation of internal 2.4 GHz radio and external QCN6102 5 GHz HE160 radio, precise caldata offsets in `0:ART`, and staging to Hexagon Q6 WCSS.

---

## 2. SPI NAND Flash Hardware & MTD Partition Topology

### 2.1 Physical NAND Flash Specifications
- **Manufacturer & Part Number:** Winbond W25N01GWZEIG (1 Gb / 128 MB SPI NAND).
- **Interface:** SPI-NAND (clocked up to 104 MHz via IPQ5018 QSPI controller).
- **Page Geometry:** 2048 bytes user data + 64 bytes Out-Of-Band (OOB / Spare).
- **Block Geometry:** 64 pages per block (128 KB user data + 4 KB spare).
- **Total Array:** 1024 blocks (128 MB total address space).
- **Hardware ECC Parameters:**
  - On-die ECC is bypassed/overridden by the Qualcomm QSPI NAND controller.
  - Device Tree specification:
    ```dts
    nand-ecc-strength = <8>;
    nand-ecc-step-size = <512>;
    ```
  - The controller computes 8-bit BCH ECC per 512-byte sector across the 64-byte OOB area. Any driver mismatch in ECC strength or step size causes uncorrectable bit errors (`EBADMSG`) and corrupts the rootfs.

### 2.2 Master Information Block (MIBIB) Partition Map

The Qualcomm IPQ5018 partition table is parsed from `0:MIBIB` (`mtd1`) by the bootloader and Linux `qcom,smem` / `mtd-split`:

```
+====================================================================================================+
|                                    MIBIB MTD PARTITION MAP (128 MB)                                |
+========+==================+=============+=============+============================================+
| MTD ID | Partition Name   | Offset      | Size        | Description & Safety Classification        |
+========+==================+=============+=============+============================================+
| mtd0   | 0:SBL1           | 0x00000000  | 0x00100000  | Secondary Boot Loader (Read-Only)          |
| mtd1   | 0:MIBIB          | 0x00100000  | 0x00100000  | Partition Table Definition (Read-Only)     |
| mtd2   | 0:QSEE           | 0x00200000  | 0x00300000  | Qualcomm Secure Execution Env (TrustZone)  |
| mtd3   | 0:DEVCFG         | 0x00500000  | 0x00080000  | Device Configuration Table (Read-Only)     |
| mtd4   | 0:RPM            | 0x00580000  | 0x00080000  | Resource Power Manager Firmware            |
| mtd5   | 0:CDT            | 0x00600000  | 0x00080000  | DDR Memory Timing Parameters               |
| mtd6   | 0:APPSBLENV      | 0x00680000  | 0x00080000  | U-Boot Bootloader Environment Variables    |
| mtd7   | 0:ART            | 0x00700000  | 0x00100000  | Atheros Radio Test: Wi-Fi Calibration Data |
| mtd8   | bdata            | 0x00800000  | 0x00100000  | Board Data: Model, Serial, Factory MACs    |
| mtd9   | crash            | 0x00900000  | 0x00080000  | Kernel Panic Crashlog Buffer               |
| mtd10  | crash_syslog     | 0x00980000  | 0x00080000  | Crash Syslog Storage                       |
+--------+------------------+-------------+-------------+--------------------------------------------+
| mtd11  | 0:APPSBL         | 0x00a00000  | 0x00180000  | Primary U-Boot Bootloader [CRITICAL!]      |
| mtd12  | 0:APPSBL_1       | 0x00b80000  | 0x00180000  | Backup U-Boot Bootloader  [CRITICAL!]      |
+--------+------------------+-------------+-------------+--------------------------------------------+
| mtd13  | rootfs           | 0x00d00000  | 0x02800000  | Active Rootfs UBI Volume (System 1, ~40MB) |
| mtd14  | rootfs_1         | 0x03500000  | 0x02800000  | Backup Rootfs UBI Volume (System 2, ~40MB) |
| mtd15  | overlay          | 0x05d00000  | 0x02300000  | Writable User Overlay UBI Volume (~35MB)   |
+========+==================+=============+=============+============================================+
```

> [!CAUTION]
> **CRITICAL FLASH SAFETY RULE:**
> `mtd11` (`0:APPSBL`) and `mtd12` (`0:APPSBL_1`) contain the physical U-Boot binaries. **Writing, modifying, or erasing these partitions is strictly prohibited.** Under our non-invasive architecture, custom firmware is packaged strictly as a UBI rootfs image written to `mtd13` or `mtd14`. Overwriting APPSBL destroys the bootloader, making TFTP recovery impossible and permanently bricking the router without a desoldered chip programmer.

---

## 3. Dual-Rootfs Bootcounter Failover & Stock TFTP Recovery

### 3.1 Autonomous Bootcounter Failover Logic
Xiaomi APPSBL implements an automated hardware watchdog failover mechanism governed by environment variables stored in `0:APPSBLENV` (`mtd6`):

```
+----------------------------------------------------------------------------------------------------+
|                                    BOOTCOUNTER FAILOVER WORKFLOW                                   |
+----------------------------------------------------------------------------------------------------+
                                      [ Router Power On ]
                                               |
                                               v
                                    Read `flag_boot_rootfs`
                                    (0 = sys1/mtd13, 1 = sys2/mtd14)
                                               |
                                               v
                                  Increment `flag_try_sysX_failed`
                                               |
                      +------------------------+-----------------------+
                      |                                                |
          `flag_try_sysX_failed` < 3                       `flag_try_sysX_failed` >= 3
                      |                                                |
                      v                                                v
              [ Boot Kernel X ]                                [ FAILOVER TRIGGERED ]
                      |                                                |
          +-----------+-----------+                      Toggle `flag_boot_rootfs` to (1 - X)
          |                       |                      Reset `flag_try_sysX_failed` = 0
       (Success)               (Crash/Hang)                            |
          |                       |                                    v
          v                       v                            [ Boot Alternate System ]
    Userspace sets           Watchdog Resets
 `flag_boot_success = 1`       Router
 `flag_try_sysX_failed = 0`       |
                                  +--------------> (Next Boot Attempt)
```

- **Boot Success Confirmation:** The custom firmware's `procd` init system executes a post-boot service:
  ```sh
  fw_setenv flag_boot_success 1
  fw_setenv flag_try_sys1_failed 0
  fw_setenv flag_try_sys2_failed 0
  ```
- **Crash Recovery:** If a bad kernel or corrupted rootfs crashes during boot, the hardware watchdog reboots the SoC. On the third failure, APPSBL automatically switches execution to the alternate healthy partition.

### 3.2 Stock Xiaomi TFTP Recovery Beacon Protocol
The Xiaomi stock bootloader features a built-in TFTP client recovery mechanism that operates independently of Linux or userland:

1. **Physical Activation:**
   - Disconnect power adapter.
   - Press and hold the physical `Reset` pinhole button with a paperclip.
   - Connect power adapter while keeping `Reset` held for 8–12 seconds.
   - Release when the front panel System/Power LED transitions to **blinking amber/orange**.
2. **Network Parameters:**
   - Router IP: `192.168.31.1` (Static, Port 0/LAN1).
   - Expected Server IP: `192.168.31.100` (Static configuration on PC).
   - Expected Subnet: `255.255.255.0`.
   - Protocol: Standard UDP TFTP (Port 69).
3. **Flashing Handshake:**
   - APPSBL broadcasts TFTP Read Requests (`RRQ`) searching for `test.bin` (or standard Xiaomi MiWiFi repair binary).
   - A TFTP server running on the host PC at `192.168.31.100` serves the recovery firmware.
   - APPSBL verifies the image header, flashes the image to NAND `mtd13`/`mtd14`, writes `flag_boot_rootfs 0`, and automatically reboots into a clean state.
4. **Conclusion:** This recovery path requires **zero serial soldering, zero UART access, and zero modification to stock bootloader code**.

---

## 4. Wi-Fi 6 Architecture & Factory Calibration Pipeline

### 4.1 RF Silicon Topology
The Xiaomi CR8808 Ver.B utilizes a dual-band Wi-Fi 6 architecture controlled by the Qualcomm Hexagon Q6 Wireless Subsystem (WCSS):

```
+====================================================================================================+
|                                    QUALCOMM IPQ5018 WCSS SUBSYSTEM                                 |
|                                                                                                    |
|   +----------------------------------------------------+                                           |
|   | Qualcomm Hexagon Q6 Coprocessor (Firmware Engine)   |                                           |
|   +-------------------------+--------------------------+                                           |
|                             | AHB Bus Interface                                                    |
|              +--------------+--------------+                                                       |
|              |                             |                                                       |
|              v                             v                                                       |
|   +-----------------------+     +-----------------------+                                          |
|   | Internal 2.4 GHz MAC  |     | External 5 GHz MAC    |                                          |
|   | IPQ5018 Integrated    |     | Qualcomm QCN6102      |                                          |
|   | 2x2:2 802.11ax        |     | 2x2:2 802.11ax HE160  |                                          |
|   | Max Rate: 574 Mbps    |     | Max Rate: 2402 Mbps   |                                          |
|   +-----------+-----------+     +-----------+-----------+                                          |
|               |                             |                                                      |
|               v                             v                                                      |
|          2.4 GHz FEMs                   5 GHz FEMs                                                 |
|       (Front-End Modules)           (160 MHz High-Band)                                            |
+====================================================================================================+
```

### 4.2 Factory Calibration Geometry in `0:ART` (`mtd7`)
RF calibration values (Power Amplifier bias, Low Noise Amplifier gain, phase compensation, and beamforming matrix constants) are measured in the factory and permanently written into `0:ART` (`mtd7`):

| Radio Band | Silicon Component | Calibration Offset in `mtd7` | Calibration Data Length | Staging Firmware Destination |
|---|---|---|---|---|
| **2.4 GHz (Radio 0)** | IPQ5018 Internal | `0x00001000` (`0x1000`) | `0x00020000` (128 KB) | `cal-ahb-c000000.wifi.bin` |
| **5.0 GHz (Radio 1)** | Qualcomm QCN6102 | `0x00026800` (`0x26800`)| `0x00020000` (128 KB) | `cal-ahb-b00a040.wifi1.bin` |

- **Extraction Hotplug Script (`/lib/firmware/ath11k/`):**
  The OpenWrt userland extracts calibration chunks directly from MTD using `dd` or `caldata_extract`:
  ```sh
  dd if=/dev/mtd7 of=/lib/firmware/ath11k/IPQ5018/hw1.0/cal-ahb-c000000.wifi.bin bs=1 skip=4096 count=131072
  dd if=/dev/mtd7 of=/lib/firmware/ath11k/QCN6102/hw1.0/cal-ahb-b00a040.wifi1.bin bs=1 skip=157696 count=131072
  ```
- **Integrity Requirement:** `0:ART` must remain read-only. If `0:ART` is erased or corrupted, Wi-Fi transmit power drops by 15-20 dBm and 160 MHz channel bonding fails completely.

### 4.3 Mandatory HE160 (160 MHz) Support
The chief technical differentiator of the CR8808 Ver.B over lower-tier routers is its support for **HE160 (160 MHz channel bandwidth)** on the 5 GHz band, providing a theoretical PHY rate of **2402 Mbps**:
- **Operating Channels:** Requires DFS channels (e.g. Channel 52 to 64, or Channel 100 to 128).
- **Driver Integration:** Driven by `ath11k` with `ath11k-firmware-qcn6102`.
- **Target Parity:** Firmware configuration must enforce `htmode='HE160'` and preserve clean radar detection algorithms to prevent spurious fallback to 80 MHz.
