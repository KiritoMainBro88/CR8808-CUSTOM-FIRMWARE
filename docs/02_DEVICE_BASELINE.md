# 02 — Device Baseline and Evidence Register

- **Document ID:** `docs/02_DEVICE_BASELINE.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 + Motorcomm YT9215S/SC)
- **Status:** Authoritative Hardware Evidence Register
- **Revision:** Round 3 Review (Exact Port Mapping & DRAM vs NAND BDF Disambiguation)

---

## 1. Product Identity & Hardware Topology

- **Commercial Device:** Xiaomi CR8808 Ver.B — `OWNER_CONFIRMED`.
- **Internal Model Identifier:** `CR8818` (board string `ap-mp03.3`) — `REPORTED_UNVERIFIED`.
- **Important Distinction:** Do not conflate the commercial product name (CR8808 Ver.B) with the CR8806 (which uses Qualcomm QCA8337 switch) or assume all CR881x variants share identical board revisions.

---

## 2. Preliminary Hardware Baseline & Evidence Status

| Component | Hardware Specification & Mapping | Evidence Status | Technical Notes |
|---|---|---|---|
| **SoC** | Qualcomm IPQ5018 | `REPORTED_UNVERIFIED` | Dual-core Cortex-A53 @ 1.0 GHz (AArch64 capable). |
| **Physical RAM** | 256 MB DDR3L | `REPORTED_UNVERIFIED` | ~182 MB usable by Linux kernel after U-Boot/TZ reservations. |
| **Physical Flash (NAND)** | Winbond W25N01GWZEIG (128 MB SPI NAND) | `REPORTED_UNVERIFIED` | MTD fixed layout with dual UBI system slots (`rootfs`, `rootfs_1`). |
| **Switch IC** | Motorcomm YT9215S or YT9215SC at MDIO `0x1d` | `SOURCE_VERIFIED` (DTS) / `REPORTED_UNVERIFIED` (Physical Suffix) | Managed over bit-banged MDIO Bus 1 (GPIO 36 MDC, GPIO 37 MDIO, GPIO 39 reset). |
| **Internal SoC PHY** | Qualcomm IPQ5018 Internal GE PHY (PHY ID `0x004dd0c0`) | `DEVICE_READBACK` (Prior stock audit) | Attached to internal MDIO bus `88000.mdio:07`. Distinct from external switch. |
| **CPU Conduit 1 (LAN)** | Switch Port 8 $\rightarrow$ IPQ5018 GMAC1 (`dp2` / `eth1`) | `SOURCE_VERIFIED` (zcop DTS) | **SGMII fixed-link 1000 Mbps** full-duplex (`phy-mode = "sgmii"`). NOT 2500Base-X. |
| **CPU Conduit 2 (WAN)** | Switch Port 4 $\rightarrow$ IPQ5018 GMAC0 (`dp1` / `eth0`) | `SOURCE_VERIFIED` (zcop DTS) | Internal GE PHY fixed-link 1000 Mbps (`phy-mode = "internal"`). |
| **Switch Port 0** | Physical Port LAN 1 | `SOURCE_VERIFIED` (zcop DTS) | `port@0`: `label = "lan1"`, internal PHY 0. |
| **Switch Port 1** | Physical Port LAN 2 | `SOURCE_VERIFIED` (zcop DTS) | `port@1`: `label = "lan2"`, internal PHY 1. |
| **Switch Port 2** | Physical Port LAN 3 | `SOURCE_VERIFIED` (zcop DTS) | `port@2`: `label = "lan3"`, internal PHY 2. |
| **Switch Port 3** | Physical Port WAN | `SOURCE_VERIFIED` (zcop DTS) | `port@3`: `label = "wan"`, internal PHY 3. |
| **Switch Port 10** | Internal MCU / Switch Control | `SOURCE_VERIFIED` (zcop DTS) | Internal management channel. |
| **2.4 GHz Wi-Fi Radio** | Integrated IPQ5018 AHB Radio (`wifi0`) | `REPORTED_UNVERIFIED` | 2x2 802.11ax (up to 574 Mbps). |
| **5 GHz Wi-Fi Radio** | Qualcomm QCN6102 / QCN6122 (`wifi1`) | `REPORTED_UNVERIFIED` | 2x2 802.11ax HE160 (up to 2402 Mbps, 160 MHz channel width). |
| **RF Calibration (NAND)** | Partition `0:ART` at offset `0x00780000`, size 1 MiB | `SOURCE_VERIFIED` (DTS) | Read-only factory calibration partition on Winbond SPI NAND. |
| **Wi-Fi BDF (RAM Staging)** | 2.4 GHz at `0x4c400000`, 5 GHz at `0x4d100000` | `SOURCE_VERIFIED` (DTS) | **DRAM memory staging addresses** for ath11k Q6 WCSS firmware, NOT NAND offsets. |
| **Active Stock Firmware** | Xiaomi RA82 Global v1.4.31 (Linux 4.4.60) | `REPORTED_UNVERIFIED` | Active on NAND Slot 1 (`flag_boot_rootfs=1`). |

---

## 3. Read-Only Evidence Required During Phase P2

Execution is strictly conditional on explicit authorization of [`docs/R0_READONLY_AUDIT_MANIFEST.md`](R0_READONLY_AUDIT_MANIFEST.md):
- `ubus call system board`
- `/etc/board.json`
- `nvram get model; nvram get flag_boot_rootfs; nvram get flag_boot_success`
- `uname -a`, `/proc/version`, `/proc/cpuinfo`
- `cat /proc/meminfo`, `cat /proc/mtd`, `dmesg`
- `lsmod` (inspect loaded `yt_switch`, `qca-ssdk`, `nss-dp` drivers)
- Radio / driver / HE160 live state via `uci show wireless` and `iwconfig`
- Network interface topology (`ip addr show; ip route show`)
- `/proc/smi` switch register readback (passively inspect chip ID)

---

## 4. Evidence Classification Taxonomy

- **`OWNER_CONFIRMED`:** Directly certified by device owner.
- **`DEVICE_READBACK`:** Extracted directly from live device hardware interrogation.
- **`SOURCE_VERIFIED`:** Verified directly against board DTS and upstream kernel driver source code.
- **`MEASURED`:** Empirically verified through active command or tool execution.
- **`REPORTED_UNVERIFIED`:** Reported by community or prior sessions, awaiting live device confirmation.
- **`INFERRED`:** Derived by technical deduction; not yet verified against hardware.
- **`UNKNOWN`:** Inconclusive or conflicting data; requires empirical hardware test.
