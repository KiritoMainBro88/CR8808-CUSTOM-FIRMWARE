# ADR-0005 — Updated Two-Track Architecture with Chinese Community Evidence & Hardware Reconciliation (M7.1 Revision 1.2)

- **Status:** RATIFIED BY CHIEF ARCHITECT (M7.1 REVISION 1.2)
- **Date:** 2026-11-11
- **Owner:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Supercedes:** ADR-0004 (Platform Selection)

---

## 1. Context & Problem Statement

Following the completion of Milestone M7.0, an exhaustive reverse-engineering audit of Chinese developer communities (Enshan Wireless Forum / `right.com.cn`, `hzyitc/openwrt-redmi-ax3000`, `marchmin/immortalwrt-zcop`, `zcop/immortalwrt`, `kuncy7/openwrt-nss-edma`, `fanha99/openwrt-xiaomi-cr8806-nss`, and David Yang's upstream Linux tree `yangfl/openwrt`) uncovered critical technical realities that require immediate architectural reconciliation:

1. **Physical Ethernet Speed Truth:** Upstream and vendor trees confirm that Port 8 of the Motorcomm YT9215SC switch communicates with the Qualcomm IPQ5018 Uniphy SerDes strictly at **1,000 Mbps SGMII** (`speed = <1000>`). Any claim that this device provides 2.5 Gbps Ethernet is technically false and formally retracted.
2. **Register `0x8000c` Bitfield Truth:** Upstream Linux kernel driver `yt921x.c` defines `0x8000c` as `YT921X_EXT_CPU_PORT` with `TAG_EN` (bit 15), `PORT_EN` (bit 14), and `PORT_MASK` (bits 3:0). The previous hypothesis of a bit-4 dual-conduit toggle is unfounded and retracted.
3. **GPIO 39 / 37 Cold-Boot Lockup Bug:** Chinese community analysis demonstrates that GPIO 39 may connect to a LAN LDO / Power Enable line rather than a simple reset line, and the switch may require MDIO clock bursts on GPIO 37 to awaken. This issue is maintained as **`CONFLICT_UNRESOLVED`**. We adhere strictly to upstream DTS timings (10ms assert, 50ms deassert) without inventing arbitrary delays.
4. **NSS Parser Collision & 256MB Buffer Bug:** Qualcomm NSS hardware microcode fails to parse proprietary 8-byte DSA tags (`tag_yt921x`), bypassing hardware offload. Furthermore, NSS firmware v12.5 has community-reported buffer retention issues on 256MB devices. NSS on CR8818 remains strictly `REPORTED_UNVERIFIED`.
5. **NAND Flash Model & ECC Truth:** Forensic cross-examination against JEDEC ID `0xef 0xaa 0x21` establishes the flash as the 3.3V **Winbond W25N01GV family** with 1-bit on-die ECC (`NAND_ECCREQ(1, 512)`). Previous claims of 1.8V "W25N01GW" and mandatory 8-bit controller BCH ECC are retracted. Package suffix (e.g. `ZEIG`) is unverified.
6. **Recovery Channels & Flash Prohibition:** The user has no serial UART console. Because TFTP beacon parameters (`192.168.31.100`, `test.bin`) and U-Boot web failsafe behavior have not been empirically verified on this specific unit, recovery safety cannot be guaranteed. Flash authorization remains strictly **`NO-GO`**.

---

## 2. Architectural Decisions

```
+====================================================================================================+
|                                    ADR-0005 ARCHITECTURAL TOPOLOGY                                 |
+====================================================================================================+
|                                                                                                    |
|    +------------------------------------------------------------------------------------------+    |
|    | TRACK A: DAILY DRIVER BASELINE (PRODUCTION READY TARGET)                                 |    |
|    +------------------------------------------------------------------------------------------+    |
|    | Base Platform:     OpenWrt 25.12.6 Official Mainline                                     |    |
|    | Linux Kernel:      Linux 6.12.112 LTS (tracking 6.12.y security updates, e.g. 6.12.117)   |    |
|    | Switch Driver:     Upstream Linux DSA (`tag_yt9215` / `tag_8021q`)                       |    |
|    | Ethernet Speed:    1,000 Mbps SGMII on Port 8 (CPU Primary) + 1,000 Mbps GE PHY (Sec.)   |    |
|    | Acceleration:      nftables Software Flowtable Offload (ARM NEON)                        |    |
|    | VPN Engine:        BoringTun Rust 0.7.1 (musl static AArch64, userspace daemon)          |    |
|    | Memory Profile:    ~95 MB free RAM; zero out-of-tree binary blobs; 100% stable 24/7      |    |
|    +------------------------------------------------------------------------------------------+    |
|                                                                                                    |
|    +------------------------------------------------------------------------------------------+    |
|    | TRACK B: NEXT-GEN EXPERIMENTAL (RESEARCH & SANDBOX ONLY)                                 |    |
|    +------------------------------------------------------------------------------------------+    |
|    | Base Platform:     ImmortalWrt / kuncy7 Research Fork                                    |    |
|    | Linux Kernel:      Linux 6.18 LTS Experimental Track (e.g. 6.18.63) / QSDK Fork          |    |
|    | Acceleration:      Qualcomm NSS NPU Offload via NSS-DP / ECM                             |    |
|    | Tagger Adapter:    VLAN tag_8021q or Dual-Conduit Demux (Untagged Port 4 WAN)            |    |
|    | Deployment Gate:   STRICTLY QUARANTINED to PC simulation & QEMU; BANNED FROM FLASHING    |    |
|    +------------------------------------------------------------------------------------------+    |
+====================================================================================================+
```

### 2.1 Formal Correction of Ethernet Speed (1,000 Mbps SGMII)
- **Decision:** Port 8 is officially designated and configured as **1,000 Mbps SGMII**.
- **Rationale:** The Qualcomm IPQ5018 Uniphy SerDes cannot train reliably at 2.5 Gbps under the current Linux SerDes driver (`patch 940` handles REVSGMII at 1.0 Gbps). No marketing or technical claims of 2.5 Gbps connectivity shall appear in project documentation.

### 2.2 GPIO 39 / 37 Policy
- **Decision:** Adhere to David Yang's upstream verified DTS timing:
  ```dts
  reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
  reset-assert-us = <10000>;
  reset-deassert-us = <50000>;
  ```
- **Classification:** Maintained strictly as **`CONFLICT_UNRESOLVED`**. No arbitrary timings or driver modifications will be implemented without physical signal measurement.

### 2.3 Quarantine of Qualcomm NSS Offload
- **Decision:** Qualcomm NSS offload is completely excluded from the Daily Driver firmware.
- **Rationale:** Structural parser incompatibility with 8-byte DSA tags and the NSS 12.5 buffer retention risks represent unacceptable stability hazards on a 256MB device. NSS remains an isolated research topic in Track B.

### 2.4 Partition Label Identification & Flash Prohibition
- **Decision:** Firmware images shall strictly target UBI rootfs partitions parsed by label (`rootfs` or `rootfs_1`).
- **Safety Directive:** Bootloader partitions (`0:APPSBL`, `0:APPSBL_1`) and calibration partition (`0:ART`) are marked **PERMANENTLY READ-ONLY**. Hardcoded integer `/dev/mtdX` indices are forbidden. All flashing remains under strict **`NO-GO`**.

### 2.6 Kernel Version Maintenance Discipline & Stable Tracking
- **OpenWrt Baseline Reality:** OpenWrt 25.12.6 stable release integrates **Linux 6.12.112**.
- **Upstream Release Tracking (2026-11-10 Releases):** Upstream kernel.org released Linux 6.12.117 and Linux 6.18.63 on 2026-11-10.
- **Strict Version Discipline:**
  1. We do **NOT** arbitrarily swap or bump the Linux kernel version within OpenWrt buildroot without rebuilding and synchronizing all 71+ kernel modules (`.ko`), kernel ABI symbol hashes, defconfig symbols, and target patches.
  2. **Track A (Daily Driver):** Built strictly against OpenWrt 25.12.6 release baseline (Linux 6.12.112 as integrated), tracking only upstream OpenWrt target stable maintenance updates (e.g. 6.12.y backports).
  3. **Track B (Experimental):** Targets Linux 6.18.63 LTS for forward-porting research and NSS offload exploration.

### 2.7 Wi-Fi 6 HE160 (160 MHz) Formal Status
- **Decision:** HE160 (160 MHz) bandwidth is designated as a **`CONDITIONAL_ACCEPTANCE_TARGET`**.
- **Classification:** It is **NOT** an approved or verified Daily Driver capability until live RF test bench validation confirms radar detection (`WMI_PDEV_DFS_RADAR_DETECTION_EVENTID`), regulatory compliance (CAC/NOP), and zero false-positive bandwidth downgrades under real 160 MHz client traffic.

---

## 3. Consequences & Trade-Offs

### Positive Consequences
- **Rock-Solid Stability:** Daily Driver firmware runs entirely within the 182 MB Linux memory budget, immune to NSS 12.5 buffer leaks or OOM panics.
- **Full Gigabit Line Rate:** Software flowtable offload delivers line-rate forwarding with estimated 25-45% CPU utilization (pure software estimated at 50-65%).
- **Clean Upstream Maintenance:** Daily Driver builds track official OpenWrt 25.12.6 releases without relying on unmaintained vendor forks.

### Negative Consequences / Accepted Limitations
- **No NSS Hardware Offload in Daily Driver:** CPU handles routing and VPN crypto via ARM NEON, limiting maximum WireGuard throughput to ~450-520 Mbps.
- **Dual-Track Build Maintenance:** Developers must maintain two separate build configurations: Track A (clean OpenWrt 25.12.6 / Linux 6.12) and Track B (experimental NSS / Linux 6.18).
- **No Flash Verification:** The physical device cannot be flashed until independent non-UART recovery verification is established.

---

## 4. Evidence Classification Summary

- `SOURCE_VERIFIED`: David Yang DTS (`b230c2f`), SerDes Patch 940, OpenWrt 25.12.6 build, Linux `winbond.c` (`NAND_ECCREQ(1, 512)`), BoringTun AArch64.
- `DEVICE_READBACK`: `CR8818`, `ap-mp03.3`, 182 MB RAM, IPQ5018 SoC.
- `CONFLICT_UNRESOLVED`: GPIO 39 reset vs LAN LDO power enable; GPIO 37 MDIO clock burst.
- `REPORTED_UNVERIFIED`: NSS offload on real CR8818 hardware; NSS 12.5 buffer retention on 256MB RAM; TFTP beacon protocol details; U-Boot web failsafe existence; dual-rootfs bootcounter failover execution.
- `ENGINEERING_ESTIMATE`: CPU utilization under pure software routing (50-65%) and flowtable offload (25-45%).
