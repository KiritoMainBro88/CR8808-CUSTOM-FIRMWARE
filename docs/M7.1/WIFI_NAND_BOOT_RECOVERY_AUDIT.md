# Wi-Fi 6, SPI NAND MTD Architecture & Recovery Audit (M7.1 Revision 1)

- **Document ID:** `docs/M7.1/WIFI_NAND_BOOT_RECOVERY_AUDIT.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, IPQ5018 + QCN6102 + Winbond W25N01GW)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical Specification & Safety Audit for Gate M7.1 Revision 1
- **Evidence Classification:** `SOURCE_VERIFIED`, `DEVICE_READBACK`, `REPORTED_UNVERIFIED`, `INFERRED`.

---

## 1. Executive Summary

This document establishes the verified hardware parameters, architecture, and safety constraints for three critical subsystems of the Xiaomi CR8808 Ver.B:
1. **SPI NAND Flash & MTD Architecture:** Official Winbond W25N01GW on-die ECC specification (`NAND_ECCREQ(1, 512)`), distinction between partition labels, physical offsets, and dynamic runtime MTD enumeration.
2. **Recovery Channels & Risk Demarcation:** Separation of Xiaomi stock TFTP recovery, U-Boot HTTP web recovery, UART console recovery, and dual-rootfs bootcounter failover. Formal retraction of the "100% recovery safety" claim.
3. **Wi-Fi 6 Subsystem:** Disambiguation of physical QCN6102 silicon from the upstream `qcn6122` firmware driver path, calibration offsets in `0:ART`, and the critical distinction between calibration geometry and DFS/HE160 regulatory enforcement.

---

## 2. SPI NAND Flash Hardware & MTD Partition Topology

### 2.1 Physical NAND Flash Specifications & ECC Truth (`DEVICE_READBACK_RECONCILED` / `SOURCE_VERIFIED`)
- **Forensic Part Family & Voltage Reconciliation:**
  - Saved device readback baseline in `docs/02_DEVICE_BASELINE.md` captured JEDEC ID **`0xef 0xaa 0x21`**.
  - According to official Winbond datasheets and Linux `drivers/mtd/nand/spi/winbond.c`:
    - **`0xef 0xaa 0x21`:** Identifies the **Winbond W25N01GV family (3.3V)**.
    - **`0xef 0xba 0x21`:** Identifies the **Winbond W25N01GW family (1.8V)**.
  - The router motherboard runs on a standard 3.3V flash power domain. The previous "W25N01GW" label was a legacy community transcription error. The physical flash is established as **Winbond W25N01GV family – JEDEC EF AA 21 (3.3V)**. The specific package ordering suffix (such as `ZEIG` for WSON8 vs `SFIF` for SOIC16) cannot be determined by JEDEC ID alone and remains unverified without microscopic package teardown. (Detailed in [`docs/M7.1/NAND_IDENTITY_RECONCILIATION.md`](NAND_IDENTITY_RECONCILIATION.md)).
- **Interface:** Standard SPI-NAND (clocked via IPQ5018 QSPI controller).
- **Array Geometry:**
  - Page Size: 2048 bytes user data + 64 bytes Out-Of-Band (OOB / Spare area).
  - Block Size: 64 pages per block (128 KB user data + 4 KB spare).
  - Total Array: 1024 blocks (128 MB total addressable flash).
- **Hardware ECC Specification (Official Winbond Datasheet & Upstream Linux Driver):**
  - According to the official Winbond W25N01GV datasheet, the chip integrates an **internal 1-bit on-die ECC engine** covering each 512-byte sector.
  - In upstream Linux kernel (`drivers/mtd/nand/spi/winbond.c`), the chip is registered as:
    ```c
    SPINAND_INFO("W25N01GV",
        SPINAND_ID(SPINAND_READID_METHOD_OPCODE_DUMMY, 0xaa, 0x21),
        NAND_MEMORG(1, 2048, 64, 64, 1024, 20, 1, 1, 1),
        NAND_ECCREQ(1, 512),
        SPINAND_INFO_OP_VARIANTS(&read_cache_variants,
                     &write_cache_variants,
                     &update_cache_variants),
        0,
        SPINAND_ECCINFO(&w25m02gv_ooblayout, NULL)),
    ```
  - **Correction Regarding ECC Strength:**
    Previous drafts erroneously claimed a mandatory "8-bit BCH controller ECC (`nand-ecc-strength = 8`)". Unless explicit controller-level override source code is verified for the IPQ5018 QSPI driver, the hardware requirement is established as **1-bit ECC per 512 bytes** (`NAND_ECCREQ(1, 512)`), provided natively by the on-die engine. The previous 8-bit claim is retracted.

---

### 2.2 Partition Labels, Physical Offsets & Dynamic Runtime MTD Enumeration

To prevent soft-bricking, flash operations must strictly distinguish between **Partition Labels**, **Physical Flash Offsets**, and **Dynamic Runtime MTD Enumeration**:

1. **Partition Labels (Authoritative):** Defined in the Master Information Block (`0:MIBIB`) and parsed by Qualcomm SBL/APPSBL and Linux kernel parsers (`qcom,smem` / `cmdlinepart`).
2. **Physical Flash Offsets:** Fixed byte offsets on the NAND flash memory array.
3. **Runtime MTD Enumeration (`mtd0`, `mtd1`, ...):** Assigned dynamically by the Linux MTD subsystem depending on driver probe order, SMEM table parsing direction, and active UBI volumes.

> [!WARNING]
> **No Hardcoded `/dev/mtdX` Indexing:**
> Community reports on Enshan for CR881x devices show divergent runtime numbering:
> - In some logs, `0:ART` is assigned to `mtd7`, while in other configurations it appears as `mtd13`.
> - `0:APPSBL` has been reported at `mtd11` or `mtd12` depending on partition table layout and active dual-boot slot.
> Therefore, scripts and documentation must **never hardcode MTD integer numbers**. Software must resolve partitions strictly by label (e.g. `find_mtd_part "0:ART"` or via `/proc/mtd` string matching).

#### Partition Topology Reference Table (Labels & Physical Geometry)

| Partition Label | Physical Offset (Typical) | Typical Size | Description & Safety Classification | Evidence Level |
|---|---|---|---|---|
| `0:SBL1` | `0x00000000` | 1024 KB | Secondary Boot Loader (Read-Only) | `SOURCE_VERIFIED` |
| `0:MIBIB` | `0x00100000` | 1024 KB | Partition Table Master Block (Read-Only) | `SOURCE_VERIFIED` |
| `0:QSEE` | `0x00200000` | 3072 KB | Qualcomm Secure Execution Environment / TrustZone | `SOURCE_VERIFIED` |
| `0:DEVCFG` | `0x00500000` | 512 KB | Device Configuration Parameters | `SOURCE_VERIFIED` |
| `0:RPM` | `0x00580000` | 512 KB | Resource Power Manager Firmware | `SOURCE_VERIFIED` |
| `0:CDT` | `0x00600000` | 512 KB | DDR Memory Configuration Data Table | `SOURCE_VERIFIED` |
| `0:APPSBLENV` | `0x00680000` | 512 KB | U-Boot Environment Variables (Boot flags) | `SOURCE_VERIFIED` |
| `0:ART` | `0x00700000` (varies) | 1024 KB | Atheros Radio Test (Factory RF Calibration) | `REPORTED_UNVERIFIED` (Offset) |
| `bdata` | `0x00800000` | 1024 KB | Board Data: Model ID, Serial Number, MACs | `REPORTED_UNVERIFIED` (Offset) |
| `crash` | `0x00900000` | 512 KB | Kernel Panic Crashlog Storage | `REPORTED_UNVERIFIED` (Offset) |
| `crash_syslog` | `0x00980000` | 512 KB | Crash Syslog Buffer | `REPORTED_UNVERIFIED` (Offset) |
| `0:APPSBL` | `0x00a00000` (varies) | 1536 KB | Primary U-Boot Bootloader [CRITICAL!] | `REPORTED_UNVERIFIED` (Offset) |
| `0:APPSBL_1` | `0x00b80000` (varies) | 1536 KB | Backup U-Boot Bootloader  [CRITICAL!] | `REPORTED_UNVERIFIED` (Offset) |
| `rootfs` | `0x00d00000` (varies) | ~40 MB | Active System Rootfs UBI Volume | `REPORTED_UNVERIFIED` (Offset) |
| `rootfs_1` | `0x03500000` (varies) | ~40 MB | Backup System Rootfs UBI Volume | `REPORTED_UNVERIFIED` (Offset) |

> [!CAUTION]
> **STRICT PROHIBITION ON BOOTLOADER PARTITIONS:**
> Modifying, flashing, or erasing `0:APPSBL` and `0:APPSBL_1` is strictly forbidden. Custom firmware development targets UBI volumes inside `rootfs` / `rootfs_1` exclusively.

---

## 3. Recovery Channels, Dual-Boot Mechanics & Risk Demarcation

Previous documentation over-claimed "100% unbrickable recovery". In reality, embedded recovery behavior varies across vendor U-Boot builds. The four distinct recovery channels are analyzed below:

```
+====================================================================================================+
|                                    RECOVERY CHANNELS TAXONOMY                                      |
+----------------------------------------------------------------------------------------------------+
| 1. Xiaomi Stock TFTP Recovery Beacon:                                                              |
|    Trigger: Power on with Reset held 8-12s.                                                        |
|    Evidence: REPORTED_UNVERIFIED. Protocol details (192.168.31.100, test.bin) lack packet traces. |
|                                                                                                    |
| 2. U-Boot HTTP Web Failsafe Recovery:                                                              |
|    Trigger: Power on with Reset held ~10s; user accesses web browser at 192.168.1.1.               |
|    Evidence: REPORTED_UNVERIFIED on stock CR8808; common in modified U-Boot builds on Enshan.     |
|                                                                                                    |
| 3. Dual-Rootfs Bootcounter Failover (flag_try_sysX_failed >= 3):                                   |
|    Trigger: Autonomous watchdog reboot on repeated kernel boot failure.                            |
|    Evidence: INFERRED / REPORTED_UNVERIFIED on this specific hardware.                            |
|                                                                                                    |
| 4. Hardware UART Serial Console:                                                                   |
|    Trigger: Physical 3.3V TTL connection to IPQ5018 UART pads (115200 8N1).                        |
|    Evidence: SOURCE_VERIFIED (Standard IPQ5018 pinout), BUT UNAVAILABLE TO USER.                 |
+====================================================================================================+
```

### 3.1 Channel 1: Xiaomi Stock TFTP Recovery (`REPORTED_UNVERIFIED`)
- **Community Claim:** Holding Reset while applying power causes U-Boot to initialize network interfaces at `192.168.31.1` and seek a TFTP server at `192.168.31.100` requesting a recovery image (`test.bin` or Xiaomi recovery file).
- **Audit Findings:** While David Yang noted that flashing unsupported images can cause a soft-brick requiring TFTP recovery, **neither David Yang nor official documentation confirms the exact IP addresses, filename, or TFTP client packet handshake for the CR8818**. Claims of confirmed TFTP parameters are downgraded to `REPORTED_UNVERIFIED`.

### 3.2 Channel 2: U-Boot HTTP Web Recovery (`REPORTED_UNVERIFIED`)
- **Community Claim:** Discussions on Enshan forum describe entering a U-Boot Web Failsafe interface at `192.168.1.1` (or `192.168.31.1`) by holding Reset.
- **Audit Findings:** In stock Xiaomi firmware, the HTTP web failsafe server is typically disabled or stripped unless replaced with a third-party open-source U-Boot (such as ImmortalWrt U-Boot or breed). It cannot be assumed to exist on stock RA82 bootloaders.

### 3.3 Channel 3: Dual-Rootfs Bootcounter Failover (`INFERRED` / `REPORTED_UNVERIFIED`)
- **Mechanism:** QSDK systems maintain boot variables in `0:APPSBLENV`:
  - `flag_boot_rootfs` (0 or 1)
  - `flag_boot_success` (0 or 1)
  - `flag_try_sys1_failed` / `flag_try_sys2_failed`
- **Audit Findings:** While this mechanism is well-documented in QSDK source trees, **its execution has not been verified via serial boot log on this exact CR8808 Ver.B unit**. Therefore, relying on bootcounter failover as a guaranteed safety net is unsafe.

### 3.4 Recovery Conclusion: Flash Remains Strictly `NO-GO`
Because the user does not possess a UART serial console and neither TFTP beacon parameters nor bootcounter failover have been empirically captured on this specific unit, **no recovery path is 100% verified**. The flash authorization remains strictly **`NO-GO`**.

---

## 4. Wi-Fi 6 Subsystem: Silicon, Firmware Paths & Regulatory Enforcement

### 4.1 Physical Silicon vs Upstream Firmware Driver Path (`SOURCE_VERIFIED`)
- **Physical Radio 0 (2.4 GHz):** IPQ5018 internal integrated 802.11ax radio (2x2:2, up to 574 Mbps).
- **Physical Radio 1 (5.0 GHz):** Qualcomm **QCN6102** external 802.11ax radio (2x2:2, up to 2402 Mbps at HE160).
- **Driver & Firmware Path Disambiguation:**
  - In upstream OpenWrt DTS (`yangfl/openwrt`, commit `6729bbe`), the 5 GHz radio node is declared using `qcom,qcn6122.dtsi`:
    ```dts
    &wifi1 {
        // Includes qcn6122 definitions
        qcom,ath11k-calibration-variant = "Xiaomi_CR8818";
    };
    ```
  - **Reason:** In Qualcomm's `ath11k` driver architecture, the QCN6102 and QCN6122 share the identical register interface and MAC architecture; `ath11k` loads firmware files categorized under the `qcn6122` or `IPQ5018` target tree.
  - **Distinction:** The physical hardware part is confirmed as **QCN6102**, while the driver/firmware loading path uses the upstream **`qcn6122`** infrastructure.

### 4.2 Factory Calibration Geometry in `0:ART` (`REPORTED_UNVERIFIED`)
Factory RF calibration data is stored in the `0:ART` partition:
- **2.4 GHz Internal Radio Offset:** `0x1000` (Length: 128 KB $\rightarrow$ `cal-ahb-c000000.wifi.bin`).
- **5.0 GHz QCN6102 Radio Offset:** `0x26800` (Length: 128 KB $\rightarrow$ `cal-ahb-b00a040.wifi1.bin`).

### 4.3 HE160 & DFS Availability: Separation of Caldata from Regulatory Enforcement
> [!IMPORTANT]
> **Calibration Data Does NOT Guarantee DFS or HE160 Operation:**
> Previous drafts incorrectly implied that extracting calibration data at offset `0x26800` automatically guarantees HE160 DFS operation. This was an invalid technical inference.
>
> In reality, 160 MHz operation across DFS channels (e.g. Channel 52 to 64, Channel 100 to 128) requires four independent prerequisites:
> 1. **Caldata Raw Opaque Blob Extraction:** The host extracts 128 KB opaque binary blobs from `0:ART` (`0x1000` / `0x26800`) and passes them undecoded to firmware. Internal RF structures (PA curves, LNA gains, IQ imbalance, CFR, phase deltas) are processed solely by firmware; their exact on-device binary layout is unverified by host software.
> 2. **Radio Target Microcode Radar Detector:** Radar pulse detection algorithms execute inside the radio target firmware (QCN6102 target firmware for 5 GHz DFS, distinct from IPQ5018 WPSS 2.4 GHz subsystem), transmitting the asynchronous `WMI_PDEV_DFS_RADAR_DETECTION_EVENTID` across the interconnect.
> 3. **Host Driver Engine (`ath11k.ko` -> `dfs.c`):** Monolithic `ath11k.ko` driver (there is no standalone `ath11k_dfs.ko` module) translates WMI radar events and interfaces with `cfg80211` / `mac80211` to trigger Channel Availability Checks (CAC: 60s standard, 10m for 5600–5650 MHz weather radar under ETSI EN 301 893) and Channel Switch Announcements (CSA with 30-minute NOP).
> 4. **Regulatory Database (`wireless-regdb`):** Country-code database defining allowed EIRP and radar channel boundaries.
>
> For a comprehensive technical audit of the DFS pipeline, see [`docs/M7.1/ATH11K_DFS_COMPATIBILITY_AUDIT.md`](ATH11K_DFS_COMPATIBILITY_AUDIT.md).
>
> **Status:** Full HE160 DFS functionality on CR8808 Ver.B is formally classified as a **`CONDITIONAL_ACCEPTANCE_TARGET / REPORTED_UNVERIFIED`**. It is NOT an approved Daily Driver capability until empirically validated with physical RF test bench and 160 MHz client packet captures.
