# Non-UART Recovery & Rollback Architecture (M7.0)

- **Document ID:** `docs/M7/RECOVERY_AND_ROLLBACK_PLAN.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018, Winbond 128 MB SPI NAND)
- **Primary Operational Constraint:** Operator has **NO UART console**, **NO SPI flash programmer**, and **depends on this router for active home internet**.
- **Current Directive Status:** **`NO-GO ON FLASHING. ALL M6/M7 ARTIFACTS MARKED NON_FLASHABLE_TEST_ARTIFACT.`**
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Recovery & Anti-Brick Specification for Gate M7.0

---

## 1. Executive Summary & Absolute Safety Rule

The Chief Architect's directive specifies:
> *"Trong M7.0: Không SSH vào Xiaomi. Không thay đổi cấu hình router. Không reboot. Không flash firmware. Không ghi NAND/NVRAM. Không thay đổi bootloader. Không yêu cầu UART. Đặc biệt, người dùng không có kinh nghiệm thao tác UART và không muốn phụ thuộc vào UART để cứu router. Do đó phải nghiên cứu phương án recovery thực tế trước khi có bất kỳ kế hoạch flash nào."*

Flashing third-party firmware onto an embedded router without a serial console is the highest-risk operation in hardware engineering. A single early-boot kernel panic, an unasserted switch reset GPIO, or a corrupted boot flag can instantly sever network communication, rendering the device unreachable over Ethernet and Wi-Fi.

This document establishes a **Defense-in-Depth, Non-UART Recovery Architecture** and defines the mandatory, non-negotiable verification gates that must be satisfied before any physical flash operation can ever be considered.

---

## 2. Flash Memory Partitioning & Real Xiaomi Bootloader Reality

The physical storage is a **Winbond W25N01GWZEIG (128 MB SPI NAND)** partitioned into dual system volumes:

```
+=================================================================================================+
|                            Winbond W25N01GWZEIG (128 MB SPI NAND)                               |
+=================================================================================================+
| Boot & Configuration (Read-Only)      | System Partition A (Slot 0)   | System Partition B (Slot 1)   |
| - 0:SBL1, 0:MIBIB, 0:BOOTCONFIG (4MB) | - rootfs (mtd17, 40 MB)       | - rootfs_1 (mtd18, 40 MB)     |
| - 0:QSEE / TrustZone (3MB)            |   (Slot 0: OpenWrt Target)    |   (Slot 1: Active Stock RA82) |
| - 0:APPSBL / U-Boot (1MB)             |                               |                               |
| - 0:ART (Calibration, 512KB) *IMMUTABLE*                              | User Overlay (mtd19, 35 MB)   |
| - bdata (Board ID, MAC, 512KB)        |                               |   (Shared user configuration) |
+=================================================================================================+
```

### 2.1 Critical Immutability Rules:
1. **`0:ART` Partition (`mtd13`):** Contains physical RF calibration data for the on-die 2.4 GHz radio and external QCN6102 5 GHz radio. If this partition is erased or corrupted, the wireless amplifiers will permanently fail or transmit out-of-spec signals. **Writing to `0:ART` is strictly forbidden.**
2. **`0:APPSBL` Partition (`mtd11`):** Contains the primary Qualcomm U-Boot bootloader. Overwriting this partition bricks the device irrevocably without an external chip programmer. **Writing to `0:APPSBL` is strictly forbidden.**

---

## 3. Analysis of Non-UART Recovery Mechanisms

Since opening the chassis and soldering a 3.3V UART serial connection (`115200 8N1`) is excluded by design, all recovery must rely on network-accessible fallback mechanisms:

```
+=================================================================================================+
|                              NON-UART RECOVERY HIERARCHY                                        |
+=================================================================================================+
| LEVEL 1: Dual-Partition Bootcounter Failover (Automatic Hardware Watchdog)                      |
| LEVEL 2: U-Boot Failsafe Button Trigger (Manual OpenWrt Safe Mode)                              |
| LEVEL 3: Stock Xiaomi TFTP Network Flasher (Xiaomi MiWiFi Repair Tool)                          |
+=================================================================================================+
```

### 3.1 Level 1: Dual-Partition Bootcounter Failover (Automated)
Xiaomi U-Boot evaluates NVRAM variables to determine boot slot and health:
- `flag_boot_rootfs`: Selects active partition (`0` = `rootfs` Slot 0; `1` = `rootfs_1` Slot 1). Currently, stock RA82 runs from Slot 1 (`flag_boot_rootfs=1`).
- `flag_boot_success`: Initialized to `0` by U-Boot on power-on. When the operating system boots completely and starts userspace, an init script writes `nvram set flag_boot_success=1` and `nvram commit`.
- `flag_try_sys1_failed` / `flag_try_sys2_failed`: If the kernel panics or crashes before userspace runs, the IPQ5018 hardware watchdog expires and resets the SoC. U-Boot increments the failure flag.
- **Failover Logic:** After 3 consecutive boot failures on Slot 0 (`flag_try_sys1_failed >= 3`), U-Boot **automatically inverts `flag_boot_rootfs` to `1`**, falling back to the untouched stock Xiaomi RA82 in Slot 1!

> [!WARNING]
> **Limitations of Bootcounter Failover:** Bootcounter failover ONLY works if the kernel panics and triggers a hardware reset. If an untested kernel hangs in an infinite loop with interrupts disabled and fails to ping the hardware watchdog, the router will sit frozen, requiring a manual power cycle.

### 3.2 Level 2: U-Boot Failsafe Safe Mode (Manual Button)
OpenWrt standard builds include a `failsafe` mode:
- If a custom package or firewall configuration locks out the user, holding the physical **Reset Button (GPIO 38)** during kernel boot halts service startup and mounts rootfs read-only with a fixed IP (`192.168.1.1`).
- Users can telnet into failsafe mode, inspect logs, and run `firstboot -y` to wipe corrupted overlays without reflashing.

### 3.3 Level 3: Stock Xiaomi TFTP Recovery (Emergency De-Bricking)
Stock Xiaomi U-Boot contains an emergency TFTP client baked into ROM/NAND:
- **How to Trigger:** Unplug power $\rightarrow$ Hold Reset button with a pin $\rightarrow$ Plug in power $\rightarrow$ Keep holding Reset for 10–12 seconds until the System LED flashes Yellow rapidly $\rightarrow$ Release button.
- **U-Boot Network Behavior:**
  - The router assigns itself IP `192.168.31.1`.
  - Sends ARP requests searching for a TFTP server at **`192.168.31.100`** (or `192.168.31.2`).
  - Broadcasts TFTP Read Requests (RRQ) searching for recovery firmware files (e.g. `firmware.bin` or `miwifi_ra82_firmware.bin`).
- **Xiaomi Official MiWiFi Repair Tool:**
  - Official Xiaomi Windows utility automates configuring the PC network adapter to `192.168.31.100 / 255.255.255.0`, running a local TFTP daemon, and serving the signed stock `.bin` firmware.
  - Once transferred into RAM, stock U-Boot flashes the recovery image into physical NAND and reboots back into factory RA82.

---

## 4. Mandatory Pre-Flight Verification Gates Before Any Flashing

Before any future milestone can authorize persistent flashing of the inactive slot (`rootfs`), all five gates below must be documented, tested, and approved in writing:

```
[ ] GATE 1: OFFLINE BIT-FOR-BIT PARTITION BACKUPS VERIFIED
    - Complete, verified image dumps of MTD partitions 0:art, bdata, 0:bootconfig,
      and 0:appsblenv securely stored on developer PC with cryptographic SHA-256 hashes.

[ ] GATE 2: STOCK FACTORY RECOVERY BINARY VERIFIED
    - Official Xiaomi RA82 Global v1.4.31 recovery image downloaded, unpacked,
      and validated against known SHA-256 checksums.

[ ] GATE 3: TFTP BEACON RECOVERY HANDSHAKE EMPIRICALLY CONFIRMED
    - PC Ethernet port connected to Router Port 1; Wireshark capture running on PC.
    - Router power-cycled with Reset held down; PC captures TFTP RRQ packets from
      192.168.31.1 searching for TFTP server 192.168.31.100.
    - Confirms that the physical router's U-Boot TFTP client is active and accessible.

[ ] GATE 4: NON-DESTRUCTIVE STAGING IN INACTIVE SLOT ONLY
    - Flashing MUST target the inactive partition (rootfs / Slot 0) ONLY.
    - Stock firmware in rootfs_1 (Slot 1) MUST remain 100% untouched.

[ ] GATE 5: ARCHITECTURE LEAD & PRODUCT OWNER DUAL APPROVAL
    - Formal written sign-off by ChatGPT (Architecture Lead) and Project Owner.
```

---

## 5. Conclusion & Safety Declaration

For Milestone M7.0, **NO FLASHING IS AUTHORIZED**. All firmware binaries generated in prior milestones (`factory.ubi`, `sysupgrade.bin`) remain classified as **`NON_FLASHABLE_TEST_ARTIFACT`**.

By establishing the dual-boot U-Boot failover and validating the stock TFTP recovery path as pre-requisites, the project eliminates reliance on UART serial console access while guaranteeing a deterministic path back to stock RA82.
