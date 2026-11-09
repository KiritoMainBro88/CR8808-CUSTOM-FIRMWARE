# Hardware & Network Topology Comparison: Stock CR8818 vs. yangfl vs. zcop

- **Document ID:** `docs/CR8818_NETWORK_TOPOLOGY_COMPARISON.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215S + QCN6102)
- **Status:** Authoritative 3-Way Hardware Topology Comparison
- **Revision:** Round 5.1 Review (Triangulation Across Stock Readback, `yangfl`, and `zcop`)

---

## 1. Executive Summary

To eliminate assumptions and resolve discrepancies between different community trees, this document provides a comprehensive, 3-way comparative verification across:
1. **Live Stock Router Readback:** Hardware interrogated directly on Xiaomi RA82 v1.4.31 (Linux 4.4.60).
2. **`yangfl` Upstream Reference (`ipq5018-cr8818.dts`):** Commit `b230c2f` by David Yang (mainline YT921x author).
3. **`zcop` Community Tree (`ipq5018-cr881x.dts`):** ImmortalWrt tree with enhanced YT921x driver.

---

## 2. Comprehensive 3-Way Hardware & Topology Comparison Table

| Subsystem / Property | Stock Router Readback (`CR8818`) | `yangfl` Reference (`ipq5018-cr8818.dts`) | `zcop` Tree (`ipq5018-cr881x.dts`) | Architectural Consensus & Verdict |
|---|---|---|---|---|
| **Commercial Product** | Xiaomi CR8808 Ver.B | Xiaomi CR8818 | Xiaomi CR881x (CR8808 / CR8809) | Same physical hardware family. |
| **Model String** | `CR8818` (`DEVICE_READBACK`) | `model = "Xiaomi CR8818";` | `model = "Xiaomi CR881X";` | **`CR8818` is the true internal hardware model.** |
| **Board Profile String** | `ap-mp03.3` (`DEVICE_READBACK`) | `DEVICE_DTS_CONFIG := config@mp03.3` | `ap-mp03.3` | **`ap-mp03.3` verified across all sources.** |
| **Compatible String** | Vendor QSDK | `"xiaomi,cr8818", "qcom,ipq5018"` | `"xiaomi,cr881x", "qcom,ipq5018"` | Standard OpenWrt uses `"xiaomi,cr8818"`. |
| **SoC** | Qualcomm IPQ5018 (2x A53 @ 1.0 GHz) | Qualcomm IPQ5018 | Qualcomm IPQ5018 | **IPQ5018 dual-core AArch64.** |
| **Physical RAM** | 256 MB DDR3L (~182 MB usable) | 256 MB DDR3L | 256 MB DDR3L | **256 MB physical DDR3L.** |
| **Physical Flash (NAND)** | Winbond W25N01GWZEIG (128 MB) | Winbond 128 MB SPI NAND | Winbond 128 MB SPI NAND | **128 MB SPI NAND.** |
| **Ethernet Switch IC** | Motorcomm YT9215 (`0x1d`) | Motorcomm YT9215 (`0x1d`) | Motorcomm YT9215 (`0x1d`) | **Motorcomm YT9215 at MDIO `0x1d`.** |
| **Internal SoC GE PHY** | PHY ID `0x004dd0c0` at `88000.mdio:07` | Port 1, `mdiobus = <&mdio0>; phy_address = <7>;` | GE PHY at `mdio0:07` | **Internal GE PHY connected to MAC0.** |
| **Switch Reset GPIO** | Vendor GPIO 39 | `reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;` | `reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;` | **GPIO 39 Active-Low.** (Community "LDO rail" was speculation in Issue #5; without schematics, hardware wiring is `UNKNOWN / SOURCE_DERIVED_DTS_RESET`). |
| **Switch Reset Delays** | Vendor driver | Assert 10ms, deassert 50ms | Assert 50ms, deassert 250ms | **Requires extended settling delay.** |
| **MAC0 Interconnect** | Internal GE PHY -> Switch Port 4 | `&dp1` (MAC0) -> GE PHY -> Port 4 (`phy-mode = "internal"`) | `&dp1` (MAC0) -> GE PHY -> Port 4 | **MAC0 connected to Port 4 via internal PHY.** |
| **MAC1 Interconnect** | Uniphy SerDes -> Switch Port 8 | `&dp2` (MAC1) -> SGMII (REVSGMII) -> Port 8 | `&dp2` (MAC1) -> SGMII 1000M -> Port 8 | **MAC1 connected to Port 8 via SGMII 1000M.** |
| **SerDes Interface Role** | Vendor SSDK driver | **REVSGMII** (via patch 940 abuse) | SGMII / 2500Base-X register overrides | **Switch Port 8 operates in PHY role (REVSGMII).** |
| **Switch Port 0** | Physical LAN 1 | `port@0`: `label = "lan1"`, internal PHY 0 | `port@0`: `label = "lan1"`, internal PHY 0 | **Physical LAN Port 1.** |
| **Switch Port 1** | Physical LAN 2 | `port@1`: `label = "lan2"`, internal PHY 1 | `port@1`: `label = "lan2"`, internal PHY 1 | **Physical LAN Port 2.** |
| **Switch Port 2** | Physical LAN 3 | `port@2`: `label = "lan3"`, internal PHY 2 | `port@2`: `label = "lan3"`, internal PHY 2 | **Physical LAN Port 3.** |
| **Switch Port 3** | Physical WAN | `port@3`: `label = "wan"`, internal PHY 3 | `port@3`: `label = "wan"`, internal PHY 3 | **Physical WAN Port.** |
| **Switch Port 4** | Secondary CPU link (Internal PHY) | `port@4`: `label = "cpu"`, internal PHY 4 | `port@4`: `label = "cpu2"` / secondary conduit | **Dedicated CPU link to MAC0.** |
| **Switch Port 8** | Primary CPU link (SGMII SerDes) | `port@8`: `ethernet = <&dp2>`, SGMII 1000M | `port@8`: `ethernet = <&dp2>`, SGMII 1000M | **Primary DSA CPU conduit to MAC1.** |
| **Switch Port 10** | Internal MCU Channel | Unconfigured in DTS | `port@10`: MCU channel | Internal management state. |
| **Wi-Fi 2.4 GHz Radio** | IPQ5018 AHB (`wifi0`), 2x2 11ax | `wifi0`: `ath11k_ahb` (`Xiaomi-CR8818`) | `wifi0`: integrated AHB radio | **IPQ5018 integrated 2.4 GHz AHB device.** |
| **2.4 GHz Firmware Cal Request** | Stock NVRAM | `ath11k/IPQ5018/hw1.0/cal-ahb-c000000.wifi.bin` | `cal-ahb-c000000.wifi.bin` | **Exact request: `cal-ahb-c000000.wifi.bin`.** |
| **2.4 GHz BDF DRAM Addr** | `0x4c400000` | `qcom,bdf-addr = <0x4c400000>;` | `0x4c400000` | **Physical DRAM `0x4c400000` (2 MiB).** |
| **2.4 GHz ART Cal Offset** | Partition `0:ART` | Offset **`0x1000`**, Length **`0x20000`** (128K) | Offset `0x1000`, Length `0x20000` | **Offset `0x1000`, length `0x20000`.** |
| **Wi-Fi 5 GHz Radio** | Qualcomm QCN6102 (`DEVICE_READBACK`) | `wifi1`: AHB companion via Q6 WPSS | `wifi1`: AHB companion via Q6 WPSS | **Physical QCN6102; probed as AHB platform device via Hexagon Q6 WPSS/Remoteproc by `ath11k_ahb`. (PCIe ID `UNKNOWN / INCONCLUSIVE`).** |
| **5 GHz Firmware Cal Request** | Stock NVRAM | `ath11k/QCN6122/hw1.0/cal-ahb-b00a040.wifi1.bin` (or `.wifi.bin` mainline) | `cal-ahb-b00a040.wifi1.bin` | **Exact request: `cal-ahb-b00a040.wifi1.bin` (OpenWrt 6.12) / `.wifi.bin` (mainline).** |
| **5 GHz BDF DRAM Addr** | `0x4d100000` | `qcom,bdf-addr = <0x4d100000>;` | `0x4d100000` | **Physical DRAM `0x4d100000` (2 MiB).** |
| **5 GHz ART Cal Offset** | Partition `0:ART` | Offset **`0x26800`**, Length **`0x20000`** (128K) | Offset `0x26800`, Length `0x20000` | **Offset `0x26800`, length `0x20000`.** |
| **Wi-Fi Cal MAC Patch** | N/A (factory NVRAM) | **NONE (Raw `caldata_extract` directly)** | None | **Do NOT patch MAC in caldata hotplug.** |
| **NSS Acceleration** | Active (QSDK proprietary) | **NONE (Pure Linux routing / flowtable)** | Claimed dual-conduit; `NSS_NOT_VERIFIED` | **No confirmed NSS offload on clean OpenWrt.** |

---

## 3. Physical Hardware Interconnect Architecture

```
           +-----------------------------------------------------------+
           |                 Qualcomm IPQ5018 SoC                      |
           |                                                           |
           |   +----------+                           +------------+   |
           |   |   MAC0   |                           |    MAC1    |   |
           |   +----+-----+                           +-----+------+   |
           |        |                                       |          |
           |   +----+-----+                           +-----+------+   |
           |   |  GE PHY  | (88000.mdio:07)           |   Uniphy   |   |
           |   |0x004dd0c0|                           |   SerDes   |   |
           |   +----+-----+                           +-----+------+   |
           +--------|---------------------------------------|----------+
                    | (MDI / Internal Fixed-Link)           | (SGMII 1000M - REVSGMII)
           +--------|---------------------------------------|----------+
           |   +----+-----+                           +-----+------+   |
           |   |  Port 4  |                           |   Port 8   |   |
           |   |  (Phy 4) |                           |  (SerDes)  |   |
           |   +----+-----+                           +-----+------+   |
           |        |                                       |          |
           |        |        Motorcomm YT9215 Switch        |          |
           |        |             (MDIO 0x1d)               |          |
           |        +-------------------+-------------------+          |
           |                            |                              |
           |     +------------+---------+---+------------+             |
           |     |            |             |            |             |
           |  +--+---+     +--+---+      +--+---+     +--+---+         |
           |  |Port 0|     |Port 1|      |Port 2|     |Port 3|         |
           |  |(Phy 0|     |(Phy 1|      |(Phy 2|     |(Phy 3|         |
           |  +--+---+     +--+---+      +--+---+     +--+---+         |
           +-----|------------|-------------|------------|-------------+
                 |            |             |            |
                LAN1         LAN2          LAN3         WAN
```

---

## 4. Key Engineering Insights & Discrepancies Resolved

1. **REVSGMII SerDes Mode Requirement:**
   - Both `yangfl` and community research establish that the switch Port 8 must be placed in **REVSGMII** mode because the IPQ5018 SerDes acts as MAC. In OpenWrt builds lacking a dedicated REVSGMII phylink mode, `yangfl`'s patch `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch` is an indispensable requirement.
2. **Wi-Fi Calibration Extraction Geometry:**
   - Prior project documents stated that 5 GHz caldata was extracted from offset `0x20000` with length `0x10000`.
   - **Correction:** The true hardware offset in partition `0:art` is **`0x26800`** with length **`0x20000`** (128 KiB).
   - Furthermore, `11-ath11k-caldata` does **not** call `ath11k_patch_mac` or any MAC address mutation on `xiaomi,cr8818`. The driver handles MAC assignment via `0:bdata` or NVMEM cells natively.
3. **QCN6102 Silicon vs. QCN6122 Firmware Path & AHB Bus Architecture:**
   - The device baseline certifies the physical silicon as **QCN6102**.
   - However, both `yangfl` and `zcop` device trees use `ath11k-firmware-qcn6122` and DTS property `qcom,ath11k-calibration-variant = "Xiaomi-CR8818"`.
   - In Qualcomm's ath11k architecture, the QCN6122 firmware binary drives both QCN6102 and QCN6122 chips because the radio baseband IP is identical.
   - **Bus Attachment:** The QCN6102/QCN6122 companion radio is **not** a standard PCIe peripheral; it is registered as an AHB platform device via Hexagon Q6 WPSS (Wireless Processor Subsystem) / Remoteproc and probed by `ath11k_ahb`.
   - **Firmware Request Names:**
     - 2.4 GHz radio: `ath11k/IPQ5018/hw1.0/cal-ahb-c000000.wifi.bin`
     - 5 GHz radio: `ath11k/QCN6122/hw1.0/cal-ahb-b00a040.wifi1.bin` in OpenWrt 6.12 (`yangfl`); renamed to `ath11k/QCN6122/hw1.0/cal-ahb-b00a040.wifi.bin` in mainline.
   - **PCIe ID Attribution Corrected:** Prior notes mentioned PCIe ID `17cb:1104`, which LKDDb and kernel sources prove belongs to QCN6024/QCN9024/QCN9074. The PCIe ID for QCN6102 is marked **`UNKNOWN / INCONCLUSIVE`**.
4. **GPIO 39 / GPIO 37 Circuit Disambiguation:**
   - Early community speculation (Issue #5) posited GPIO 39 as an "LDO power rail enable".
   - Verified DTS across `yangfl` and `zcop` explicitly defines: `reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;`.
   - In the absence of published board schematics, the exact hardware wiring is classified as **`UNKNOWN / SOURCE_DERIVED_DTS_RESET`**.

---

## 5. Physical Flash (NAND) Hardware Discrepancies & Audit

### 5.1 Stock Router Flash Hardware Profile
From live interrogation of Xiaomi CR8808 Ver.B (`CR8818`):
- **Component:** Winbond W25N01GWZEIG
- **Interface:** SPI NAND (SPI-1 bus)
- **JEDEC ID:** `0xef 0xaa 0x21`
- **Capacity:** 128 MB (1,073,741,824 bits)
- **Geometry:**
  - Page Size: 2,048 bytes (2 KiB)
  - Spare / OOB Size: 64 bytes
  - Pages per Block: 64 pages (128 KiB erase block)
  - Total Blocks: 1,024 blocks
- **ECC Architecture:** Internal On-Die HW ECC (1-bit per 512 bytes engine / 8-bit Reed-Solomon/BCH variant).

### 5.2 Comparison with Other Xiaomi IPQ50xx Devices
Other routers in Xiaomi's IPQ50xx portfolio (e.g., CR8806, AX3000, AX6000) have been observed using alternative 128 MB NAND flash ICs across production batches:
- **GigaDevice GD5F1GQ4UBYIG:** JEDEC ID `0xc8 ...`, 2K+64B or 2K+128B OOB, internal ECC.
- **ESMT F50L1G41LB:** JEDEC ID `0xc8 0x01 ...`, internal ECC.
- **MXIC MX35LF1GE4AB:** JEDEC ID `0xc2 ...`.

### 5.3 Critical Engineering Directive for Firmware Builders
> [!CAUTION]
> **NAND Flash Interoperability Warning:**
> Never assume that 128 MB SPI NAND flash chips are drop-in interchangeable across devices or firmware images. Different flash ICs require:
> 1. Specific flash driver entries in Linux SPI NAND subsystem (`drivers/mtd/nand/spi/winbond.c` vs `gigadevice.c` vs `esmt.c`).
> 2. Distinct bad block marker schemes and OOB layouts.
> 3. Appropriate on-die vs host ECC controller configuration (e.g., avoiding conflicting double-ECC or disabled ECC causing silent bit corruption).
> 4. SPI clock frequencies and dummy cycle configurations that match the vendor bootloader.
> Flashing a U-Boot or kernel DTS configured for an incompatible NAND IC will result in an unbootable boot loop with MTD probe failure.

