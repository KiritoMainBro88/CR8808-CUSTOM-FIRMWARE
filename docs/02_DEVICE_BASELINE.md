# 02 — Device Baseline and Evidence Register

- **Document ID:** `docs/02_DEVICE_BASELINE.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 + Motorcomm YT9215S/SC)
- **Status:** Authoritative Hardware Evidence Register
- **Revision:** Round 5 Review (Hardware Disambiguation Matrix: CR8806 vs. CR8818 and Wi-Fi Silicon Demarcation)

---

## 1. Product Identity & Hardware Topology

- **Commercial Device Name:** Xiaomi CR8808 Ver.B — **`OWNER_CONFIRMED`**.
- **Internal Model Identifier:** `CR8818` — **`DEVICE_READBACK`** (Confirmed via stock `ubus call system board` in prior audit).
- **Board Profile String:** `ap-mp03.3` — **`DEVICE_READBACK`** (Confirmed via stock system readback).
- **Important Hardware Distinction:**
  - Do NOT conflate the commercial product name (CR8808 Ver.B) with the CR8806 (which uses Qualcomm QCA8337 switch at MDIO `0x17`).
  - Do NOT assume all CR881x variants share identical board revisions; the switch on this device is Motorcomm YT9215 at MDIO address `0x1d`.

### 1.1 Strict Hardware Disambiguation: Xiaomi CR8806 vs. Xiaomi CR8808 Ver.B (CR8818)

| Hardware Dimension | Xiaomi CR8806 (Codename M79) | Xiaomi CR8808 Ver.B (Codename `CR8818`) |
|---|---|---|
| **Commercial Target** | Xiaomi CR8806 / China Unicom M79 | Xiaomi CR8808 Ver.B / China Mobile |
| **Internal Model ID** | `CR8806` | **`CR8818`** (`DEVICE_READBACK`) |
| **Board Profile String** | `ap-mp03.1` (or vendor M79) | **`ap-mp03.3`** (`DEVICE_READBACK`) |
| **SoC** | Qualcomm IPQ5018 (Dual-core A53 @ 1.0 GHz) | Qualcomm IPQ5018 (Dual-core A53 @ 1.0 GHz) |
| **Physical RAM / Flash** | 256 MB DDR3L / 128 MB SPI NAND | 256 MB DDR3L / 128 MB SPI NAND |
| **Ethernet Switch IC** | **Qualcomm QCA8337** | **Motorcomm YT9215S / YT9215SC** |
| **Switch Driver** | Upstream `drivers/net/dsa/qca/qca8k.c` | Backported `drivers/net/dsa/yt921x.c` |
| **Switch MDIO Address** | **`0x17`** | **`0x1d`** |
| **5 GHz Wi-Fi Radio** | Qualcomm QCN6102 (HE160) | Qualcomm QCN6102 (HE160) |
| **Community Reference** | `fanha99/openwrt-xiaomi-cr8806-nss` | `zcop/immortalwrt` (CR881x DTS) |
| **Cross-Flash Consequence** | N/A | **FATAL ETHERNET FAILURE:** Device will boot with no working Ethernet ports because the kernel seeks QCA8337 at MDIO `0x17` rather than YT9215 at MDIO `0x1d`. |
| **Engineering Mandate** | Reference for IPQ5018 SoC only | **NEVER flash CR8806 firmware to CR8818 hardware!** |

---

## 2. Hardware Subsystem Specifications & Evidence Register

| Component | Hardware Specification & Mapping | Evidence Status | Technical Notes |
|---|---|---|---|
| **Commercial Product** | Xiaomi CR8808 Ver.B | `OWNER_CONFIRMED` | Physical router deployed in owner workstation lab. |
| **Internal Model ID** | `CR8818` | `DEVICE_READBACK` | Directly extracted from stock firmware via `ubus call system board`. |
| **Board Profile** | `ap-mp03.3` | `DEVICE_READBACK` | Extracted from stock firmware metadata. |
| **SoC** | Qualcomm IPQ5018 | `DEVICE_READBACK` | Dual-core Cortex-A53 @ 1.0 GHz (AArch64 capable). |
| **Physical RAM** | 256 MB DDR3L | `DEVICE_READBACK` | `MemTotal` reported ~182 MB usable by Linux kernel after TZ/U-Boot reserved regions. |
| **Physical Flash (NAND)** | Winbond W25N01GWZEIG (128 MB SPI NAND) | `SOURCE_VERIFIED` (DTS) / `REPORTED_UNVERIFIED` (Part marking) | MTD layout with dual UBI system slots (`rootfs`, `rootfs_1`). |
| **Switch IC** | Motorcomm YT9215S or YT9215SC at MDIO `0x1d` | `SOURCE_VERIFIED` (DTS) / `UNKNOWN` (Physical Suffix) | Managed over bit-banged MDIO Bus 1 (GPIO 36 MDC, GPIO 37 MDIO, GPIO 39 reset). |
| **Internal SoC PHY** | Qualcomm IPQ5018 Internal GE PHY (PHY ID `0x004dd0c0`) | `DEVICE_READBACK` | Resides at internal MDIO bus `88000.mdio:07`. Distinct from external switch. |
| **Switch Port 0** | Physical Port LAN 1 | `SOURCE_VERIFIED` (zcop DTS) | `port@0`: `label = "lan1"`, internal PHY 0. |
| **Switch Port 1** | Physical Port LAN 2 | `SOURCE_VERIFIED` (zcop DTS) | `port@1`: `label = "lan2"`, internal PHY 1. |
| **Switch Port 2** | Physical Port LAN 3 | `SOURCE_VERIFIED` (zcop DTS) | `port@2`: `label = "lan3"`, internal PHY 2. |
| **Switch Port 3** | Physical Port WAN | `SOURCE_VERIFIED` (zcop DTS) | `port@3`: `label = "wan"`, internal PHY 3. |
| **Switch Port 4** | CPU Conduit (Secondary in zcop NSS) | `SOURCE_VERIFIED` (zcop DTS) | Fixed-link 1000 Mbps full-duplex internal GE PHY (`phy-mode = "internal"`). |
| **Switch Port 8** | CPU Conduit (Primary SGMII) | `SOURCE_VERIFIED` (zcop DTS) | **SGMII fixed-link 1000 Mbps full-duplex** (`phy-mode = "sgmii"`, `speed = <1000>`). NOT 2500Base-X. |
| **Switch Port 10** | Internal MCU / Switch Control | `SOURCE_VERIFIED` (zcop DTS) | Internal management channel. |
| **2.4 GHz Wi-Fi Radio** | Integrated IPQ5018 AHB Radio (`wifi0`) | `SOURCE_VERIFIED` (DTS) | 2x2 802.11ax (up to 574 Mbps). |
| **5 GHz Wi-Fi Radio** | Qualcomm QCN6102 / QCN6122 (`wifi1`) | `SOURCE_VERIFIED` (DTS) | 2x2 802.11ax HE160 (up to 2402 Mbps, 160 MHz channel width). |
| **RF Calibration (NAND)** | Partition `0:ART` at offset `0x00780000`, size 1 MiB | `SOURCE_VERIFIED` (DTS) | Read-only factory calibration partition on Winbond SPI NAND. |
| **Wi-Fi BDF (RAM Staging)** | 2.4 GHz at `0x4c400000`, 5 GHz at `0x4d100000` | `SOURCE_VERIFIED` (DTS) | **DRAM memory staging addresses** for ath11k Q6 WCSS firmware, NOT NAND offsets. |
| **Active Stock Firmware** | Xiaomi RA82 Global v1.4.31 (Linux 4.4.60) | `DEVICE_READBACK` | Active on NAND Slot 1 (`flag_boot_rootfs=1`). |

---

## 3. Performance Claims & Metrics Categorization

To maintain strict scientific and engineering rigor, all performance figures mentioned in project documents are categorized according to their empirical basis:

| Metric / Claim | Categorization | Empirical Basis & Target Context |
|---|---|---|
| **940 Mbps IPv4 NAT Throughput** | `ACCEPTANCE_TARGET` | Target performance goal for Phase 1 Linux software flowtable routing under line-rate GbE traffic. NOT yet measured on custom firmware. |
| **Host CPU Utilization (50–65%)** | `ENGINEERING_ESTIMATE` | Theoretical estimate based on dual-core Cortex-A53 CPU processing 1 Gbps flowtable traffic. To be empirically benchmarked in Phase P5. |
| **NSS Memory Heap (8–16 MiB)** | `SOURCE_DERIVED` | Extracted directly from device tree reservation nodes (`nss_region` / `cr881x_nss_region`) in Qualcomm QSDK / zcop source trees. |
| **BoringTun Resident Memory (<15 MB)** | `ACCEPTANCE_TARGET` | Upper bound acceptance target for BoringTun Rust daemon under load. (Prior lab readback on ARMv7 measured ~3.7 MB idle RSS). |
| **NSS Throughput (>930 Mbps @ <10% CPU)** | `ACCEPTANCE_TARGET` | Future qualification gate for experimental Phase 2 NSS offload. |
| **5,000 Concurrent Active NAT Flows** | `ACCEPTANCE_TARGET` | Stress test acceptance threshold to verify NSS ring buffer sizing on 256 MB RAM without triggering `nss_alloc_pbuf_failed`. |

---

## 4. Evidence Classification Taxonomy

- **`OWNER_CONFIRMED`:** Directly certified by device owner.
- **`DEVICE_READBACK`:** Extracted directly from live device hardware interrogation in stock firmware.
- **`SOURCE_VERIFIED`:** Verified directly against board DTS and upstream kernel driver source code.
- **`SOURCE_DERIVED`:** Calculated or extracted directly from source code DTS register maps / memory regions.
- **`ENGINEERING_ESTIMATE`:** Theoretical calculation based on CPU architecture and network subsystem design.
- **`ACCEPTANCE_TARGET`:** Performance threshold defined as a passing criterion for future testing.
- **`MEASURED`:** Empirically verified through active command or tool execution.
- **`REPORTED_UNVERIFIED`:** Reported by community or prior sessions, awaiting live device confirmation.
- **`UNKNOWN`:** Inconclusive or conflicting data; requires empirical hardware test.
