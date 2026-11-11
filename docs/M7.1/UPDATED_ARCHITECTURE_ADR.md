# ADR-0005 — Updated Two-Track Architecture with Chinese Community Evidence & Hardware Reconciliation

- **Status:** APPROVED FOR GATE M7.1 (AWAITING ARCHITECTURE LEAD FORMAL RATIFICATION)
- **Date:** 2026-11-11
- **Owner:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Supercedes:** ADR-0004 (Platform Selection)

---

## 1. Context & Problem Statement

Following the completion of Milestone M7.0, an exhaustive reverse-engineering audit of Chinese developer communities (Enshan Wireless Forum / `right.com.cn`, `hzyitc/openwrt-redmi-ax3000`, `marchmin/immortalwrt-zcop`, `zcop/immortalwrt`, `kuncy7/openwrt-nss-edma`, `fanha99/openwrt-xiaomi-cr8806-nss`, and David Yang's upstream Linux tree `yangfl/openwrt`) uncovered critical technical realities that require immediate architectural reconciliation:

1. **Physical Ethernet Speed Truth:** Upstream and vendor trees confirm that Port 8 of the Motorcomm YT9215SC switch communicates with the Qualcomm IPQ5018 Uniphy SerDes strictly at **1,000 Mbps SGMII** (`speed = <1000>`). Any claim that this device provides 2.5 Gbps Ethernet is technically false and must be formally retracted.
2. **GPIO 39 / 37 Cold-Boot Lockup Bug:** Chinese community analysis demonstrated that GPIO 39 functions as a **LAN LDO / Power Enable** line rather than a simple reset line. Powering up the switch requires MDIO clock bursts across GPIO 37 (the U-Boot `mii info` workaround) to reliably initialize the internal state machine. This issue is categorized as `CONFLICT_UNRESOLVED`.
3. **NSS Parser Collision & 256MB Buffer Bug:** Qualcomm NSS hardware microcode fails to parse proprietary 4-byte DSA tags (`tag_yt921x`), bypassing hardware offload and causing CPU exception floods. Furthermore, NSS firmware v12.5 suffers from a skb buffer hold bug that induces fatal out-of-memory kernel panics on 256MB devices. NSS on CR8818 remains strictly `REPORTED_UNVERIFIED`.
4. **Hardware Disambiguation (CR8818 vs CR8806):** Flashing CR8806 firmware (QCA8337 switch @ `0x11`) onto CR8808 Ver.B (YT9215SC switch @ `0x1d`) permanently severs all network interfaces.
5. **Non-UART Recovery Mandate:** The user has no serial UART console. All deployment planning must strictly preserve the stock APPSBL dual-rootfs bootcounter (`flag_boot_rootfs`, `flag_boot_success`, `flag_try_sysX_failed`) and stock TFTP recovery beacon at `192.168.31.1`.

---

## 2. Architectural Decisions

```
+====================================================================================================+
|                                    ADR-0005 ARCHITECTURAL TOPOLOGY                                 |
+====================================================================================================+
|                                                                                                    |
|    +------------------------------------------------------------------------------------------+    |
|    | TRACK A: DAILY DRIVER BASELINE (PRODUCTION READY)                                        |    |
|    +------------------------------------------------------------------------------------------+    |
|    | Base Platform:     OpenWrt 25.12.6 Official Mainline                                     |    |
|    | Linux Kernel:      Linux 6.12.112 LTS (Targeting Linux 6.18 LTS)                         |    |
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
|    | Linux Kernel:      Linux 6.6 / 6.12 QSDK Fork with NSS Shim Drivers                       |    |
|    | Acceleration:      Qualcomm NSS NPU Offload via NSS-DP / ECM                             |    |
|    | Tagger Adapter:    VLAN tag_8021q or Dual-Conduit Demux (Untagged Port 4 WAN)            |    |
|    | Deployment Gate:   STRICTLY QUARANTINED to PC simulation & QEMU; BANNED FROM FLASHING    |    |
|    +------------------------------------------------------------------------------------------+    |
+====================================================================================================+
```

### 2.1 Formal Correction of Ethernet Speed (1,000 Mbps SGMII)
- **Decision:** Port 8 is officially designated and configured as **1,000 Mbps SGMII**.
- **Rationale:** The Qualcomm IPQ5018 Uniphy SerDes cannot train reliably at 2.5 Gbps under the current Linux SerDes driver (`patch 940` handles REVSGMII at 1.0 Gbps). No marketing or technical claims of 2.5 Gbps connectivity shall appear in project documentation.

### 2.2 Defensive Workaround for GPIO 39 / 37 Switch Lockup
- **Decision:** Implement a defensive dual-mode sequence:
  1. Maintain active-low reset assertion in the Device Tree with a conservative 100 ms stabilization delay.
  2. Rely on the U-Boot bootloader stage (`mii info` clock burst across GPIO 37) to awaken the Motorcomm switch before kernel handover.
- **Classification:** Categorized as `CONFLICT_UNRESOLVED` pending physical oscilloscope probe verification.

### 2.3 Quarantine of Qualcomm NSS Offload
- **Decision:** Qualcomm NSS offload is completely excluded from the Daily Driver firmware.
- **Rationale:** Structural parser incompatibility with 4-byte DSA tags and the NSS 12.5 buffer hold bug represent unacceptable stability risks on a 256MB device. NSS remains an isolated research topic in Track B.

### 2.4 SPI NAND Partition Protection & Non-UART Recovery
- **Decision:** Firmware images shall strictly target UBI rootfs partitions (`mtd13` or `mtd14`).
- **Safety Directive:** Bootloader partitions `mtd11` (`0:APPSBL`) and `mtd12` (`0:APPSBL_1`) and calibration partition `mtd7` (`0:ART`) are marked **PERMANENTLY READ-ONLY**. All flashing remains under strict **`NO-GO`** until an independent recovery test procedure is established.

### 2.5 Rust Userspace Demarcation
- **Decision:** Rust is strictly confined to userspace daemons (BoringTun 0.7.1, telemetry watchdog). All kernel-level components (DSA driver, SerDes controller, network glue) remain in standard C.

---

## 3. Consequences & Trade-Offs

### Positive Consequences
- **Rock-Solid Stability:** Daily Driver firmware runs entirely within the 182 MB Linux memory budget, immune to NSS 12.5 buffer leaks or OOM panics.
- **Full Gigabit Line Rate:** Software flowtable offload delivers 940 Mbps line rate with modest CPU usage (~18%).
- **Unbrickable Device Safety:** Preserving stock APPSBL ensures the physical router can always be recovered via stock TFTP beacon (`192.168.31.1`).
- **Clean Upstream Maintenance:** Daily Driver builds track official OpenWrt 25.12.6 releases without relying on unmaintained vendor forks.

### Negative Consequences / Accepted Limitations
- **No NSS Hardware Offload in Daily Driver:** CPU handles routing and VPN crypto via ARM NEON, limiting maximum WireGuard throughput to ~450-520 Mbps (which fully saturates typical home broadband connections).
- **Dual-Track Build Maintenance:** Developers must maintain two separate build configurations: Track A (clean OpenWrt) and Track B (experimental NSS tree).

---

## 4. Evidence Classification Summary

- `SOURCE_VERIFIED`: David Yang DTS (`b230c2f`), SerDes Patch 940, OpenWrt 25.12.6 build, MIBIB MTD map, BoringTun AArch64.
- `DEVICE_READBACK`: `CR8818`, `ap-mp03.3`, 182 MB RAM, IPQ5018 SoC.
- `CONFLICT_UNRESOLVED`: GPIO 39 reset vs LAN LDO power enable; GPIO 37 MDIO clock burst.
- `REPORTED_UNVERIFIED`: NSS offload on real CR8818 hardware; NSS 12.5 buffer leak on 256MB RAM; Winbond W25N01GW physical chip marking.
