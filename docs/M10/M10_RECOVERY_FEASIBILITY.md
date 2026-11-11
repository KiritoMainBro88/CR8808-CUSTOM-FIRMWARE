# M10 Non-UART Recovery Feasibility & Failsafe Risk Audit

**Document ID:** `CR8808-M10-REC-FEAS-001`  
**Milestone:** `M10 – Hardware Enablement & Recovery Feasibility`  
**Execution Authority:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)  
**Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)  
**Status:** `AUDITED WITH 4-TIER EVIDENCE TAXONOMY`  
**Safety Boundary:** `STRICT NO-GO FLASH` (Zero router interaction, 0 SSH, 0 TFTP, 0 NAND/NVRAM writes, 0 reboots)  
**Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Winbond W25N01GV 128MB SPI NAND)  
**Repository Branch:** `feature/m10-hardware-enablement`  

---

## 1. Executive Context & Critical Constraint

The Product Owner operates under an absolute technical constraint:
> **The owner does NOT possess a 3.3V USB-TTL serial debugging cable (UART) or an external SOIC-16 / WSON-8 SPI NAND hardware programmer (e.g., CH341A).**

If the router's bootloader fails to boot the kernel and fails to provide an automated network rescue fallback, **the router is permanently bricked**.

Under the Chief Architect's directive, this audit enforces a strict 4-tier taxonomy across all recovery claims, forbidding any assertion of recovery safety without hardware verification.

---

## 2. The 4-Tier Recovery Evidence Taxonomy

```mermaid
flowchart TD
    subgraph TIER1 ["Tier 1: Documented Capability"]
        D1["Qualcomm IPQ5018 Boot Architecture"]
        D2["Xiaomi OEM Dual-Boot Partition Spec"]
    end

    subgraph TIER2 ["Tier 2: Source-Code Verified"]
        S1["U-Boot Environment (0:appsblenv @ 0x480000)"]
        S2["FIT Configuration node: config@mp03.3"]
        S3["OpenWrt sysupgrade nand.sh bootcounter logic"]
    end

    subgraph TIER3 ["Tier 3: Community-Reported"]
        C1["Xiaomi MiWiFi Repair Tool (192.168.31.100)"]
        C2["Automatic 3-strike A/B bootcounter fallback"]
    end

    subgraph TIER4 ["Tier 4: Hardware-Tested (CR8808)"]
        H1["REALITY: ZERO ON-DEVICE RECOVERY TESTS CONDUCTED"]
        H2["VERDICT: NO-GO FLASH REMAINS PERMANENT"]
    end

    TIER1 --> TIER2
    TIER2 --> TIER3
    TIER3 --> TIER4
```

### Classification Definitions:
1. **`DOCUMENTED`**: Published in official OEM datasheets, Qualcomm boot specifications, or Xiaomi service manuals.
2. **`SOURCE_VERIFIED`**: Proven by line-by-line inspection of upstream U-Boot source, Linux kernel drivers, or Device Tree code.
3. **`COMMUNITY_REPORTED`**: Documented on third-party forums (Enshan, Right.com.cn, GitHub issues) for similar IPQ5018 models; unproven on this specific unit.
4. **`HARDWARE_TESTED`**: Empirically executed, captured, and confirmed on THIS physical CR8808 Ver.B unit.

---

## 3. Comprehensive Audit of Recovery Vectors

| Recovery Channel | Mechanism / Trigger | Claimed Capability | Evidence Classification | Technical Feasibility & Residual Risk on CR8808 |
| :--- | :--- | :--- | :---: | :--- |
| **Xiaomi MiWiFi Repair Tool** | Hold physical RESET button for 8–10s on power-up until LED blinks orange | U-Boot configures static IP `192.168.31.1`, requests image via TFTP from PC `192.168.31.100:69` | `COMMUNITY_REPORTED` | **HIGH RISK:** Certain carrier-customized firmware revisions (China Mobile CR8808) disable TFTP auto-recovery in production U-Boot builds. Unverified on this physical unit. |
| **Automated A/B Failover** | Boot failure counter reaches threshold (`flag_boot_rootfs >= 3`) | U-Boot automatically flips active slot (`boot_firmware` 0 $\leftrightarrow$ 1) to load surviving partition | `SOURCE_VERIFIED` (Scripts) / `UNVERIFIED_HARDWARE` | **MEDIUM RISK:** Relies on U-Boot executing the `bootcmd` failover script. If OpenWrt overwrites or corrupts U-Boot env variables in `0:appsblenv`, auto-rollback halts. |
| **TFTP RAM Boot** | Download `initramfs-uImage.itb` to DRAM (`0x44000000`) and boot via `bootm` | Executes entire OS from DRAM; **zero bytes written to flash**; power cycle restores factory state | `SOURCE_VERIFIED` (FIT format) / `UNVERIFIED_HARDWARE` | **ZERO FLASH RISK (IF ACCESSIBLE):** The safest possible validation path. However, triggering `bootm` without a serial console requires an automated U-Boot TFTP script. |
| **OpenWrt Failsafe Mode** | Rapidly press Reset button (GPIO 38) when System LED begins flashing fast | Boots minimal SquashFS with clean ramdisk overlay; bypasses corrupted config; SSH @ `192.168.1.1` | `SOURCE_VERIFIED` (procd) / `UNVERIFIED_HARDWARE` | **CONDITIONAL:** Only functions if the Linux kernel itself boots successfully. Useless if the kernel panics during early boot. |

---

## 4. Fatal Hard-Brick Scenarios (Requiring Hardware Tools)

The following scenarios cannot be recovered without opening the device and using external hardware:

### Scenario 1: U-Boot Partition Damage (`0:appsbl` / `0:appsbl_1`)
- **Cause:** Flashing an oversized image that overflows into MTD partitions 11 or 12, or an errant `mtd write` targeting the bootloader.
- **Result:** Primary CPU cannot execute Secondary Program Loader (SBL). Board shows zero LEDs, zero Ethernet link, zero serial output.
- **Recovery Requirement:** Desoldering the Winbond W25N01GV SPI NAND chip or clamping with a SOIC-16 test clip to reflash `0:sbl1` and `0:appsbl` via CH341A programmer.

### Scenario 2: Kernel Panic During Early Boot (`Unable to mount root fs`)
- **Cause:** Bootloader loads OpenWrt kernel, but kernel command line specifies wrong UBI partition (`ubi.mtd=rootfs` when image was flashed to `ubi_kernel`, or vice versa).
- **Result:** Linux kernel panics at second 1.2 before network drivers, GPIOs, or failsafe scripts are initialized.
- **Recovery Requirement:** Serial console (UART) to interrupt U-Boot and change bootargs, OR working OEM TFTP recovery. If OEM TFTP is disabled, the router is completely inaccessible over network.

### Scenario 3: YT9215 Switch Initialization Failure
- **Cause:** Switch driver fails due to incorrect GPIO 39 reset polarity or missing post-reset delay.
- **Result:** Kernel boots into Linux userspace, but Ethernet switch registers are locked. All 4 physical RJ45 ports remain physically dark (no link lights).
- **Recovery Requirement:** Without active Ethernet ports and without Wi-Fi enabled, the router has zero network interfaces. Irrecoverable over network.

---

## 5. Non-UART Recovery Strategy & Mandatory Rules

To prevent disaster given the Product Owner's hardware constraints:

1. **Mandatory Rule 1: No NAND Flash Writes in Early Milestones:**  
   No image may be flashed into non-volatile SPI NAND (`ubi_kernel` or `rootfs`) until Milestone M12/M13.
2. **Mandatory Rule 2: Certified RAM Boot via TFTP First:**  
   Before any flash write is ever authorized, Milestone M10/M12 must prove that `openwrt-qualcommax-ipq50xx-xiaomi_cr8818-initramfs-uImage.itb` boots and initializes the Motorcomm YT9215 switch and ath11k Wi-Fi in volatile DRAM.
3. **Mandatory Rule 3: Factory Rollback Capability:**  
   The stock Xiaomi RA82 Global v1.4.31 image must be verified and staged so that if an emergency rollback is required from a running OpenWrt shell, `ubiformat /dev/mtd18` can restore the original firmware cleanly.

---

## 6. Audit Sign-Off

- [x] Strict 4-tier evidence separation enforced across all recovery mechanisms.
- [x] Zero-UART constraint explicitly acknowledged as a critical project risk.
- [x] Hard-brick failure modes identified and documented.
- [x] Non-volatile flash writes confirmed strictly prohibited.
- [x] Recovery feasibility classified as **`CONDITIONAL_UPON_HARDWARE_BENCH_TESTING`**.
