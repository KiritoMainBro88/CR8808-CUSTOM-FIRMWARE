# Xiaomi CR8818 Reference Implementations & Community Source Audit

- **Document ID:** `docs/CR8818_REFERENCE_IMPLEMENTATIONS.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215S + QCN6102)
- **Status:** Authoritative Upstream & Community Source Audit
- **Revision:** Round 5.1 Review (Audit of `yangfl/openwrt`, `zcop/immortalwrt`, and `kuncy7/openwrt-nss-edma`)

---

## 1. Executive Summary

This document performs an exhaustive technical audit of the three primary community implementations relevant to the Xiaomi CR8818 (CR8808 Ver.B):
1. **`yangfl/openwrt` (Author: David Yang / `mmyangfl`):** Commit `b230c2fbb5548200772a20546bdef17bb50a7d5f` ("qualcommax: Add support for Xiaomi CR8818"). David Yang is the author who upstreamed the Motorcomm YT921x driver and tagger to mainline Linux (Linux 6.19).
2. **`zcop/immortalwrt` (Author: `zcop`):** A heavily engineered out-of-tree port featuring `tag_yt921x_enhanced.c`, low-level register reverse engineering (`README.yt921x.md`), dual-conduit fallback, and Qualcomm NSS datapath integration.
3. **`kuncy7/openwrt-nss-edma` (Author: `kuncy7`):** An advanced NSS offload architecture integrating upstream `stmmac` with `qca-dwmac-nss` using `tag_8021q` trunking for IPQ50xx target boards.

---

## 2. In-Depth Audit: `yangfl/openwrt` (David Yang's Upstream-Aligned CR8818 Implementation)

### 2.1 Provenance and Significance
- **Source Link:** [`https://github.com/yangfl/openwrt/commit/b230c2fbb5548200772a20546bdef17bb50a7d5f`](https://github.com/yangfl/openwrt/commit/b230c2fbb5548200772a20546bdef17bb50a7d5f)
- **Author:** David Yang (`mmyangfl@gmail.com`), the primary contributor who authored:
  - `drivers/net/dsa/yt921x.c` (Linux mainline)
  - `net/dsa/tag_yt921x.c` (Linux mainline)
  - Reviewed by Andrew Lunn, signed off by Jakub Kicinski for Linux 6.19 mainline inclusion.
- **Architectural Value:** This is the **most authoritative, upstream-aligned implementation of CR8818 in existence**. Unlike generic board ports, this commit was authored by the driver author specifically targeting the Xiaomi CR8818.

### 2.2 Files Introduced in Commit `b230c2f`
1. `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq5018-cr8818.dts`: Dedicated DTS for CR8818.
2. `target/linux/generic/hack-6.12/940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`: Essential SerDes patch for IPQ5018 <-> YT9215 communication.
3. `target/linux/generic/backport-6.12/830-01-v6.19-net-dsa-tag_yt921x-add-support-for-Motorcomm-YT921x-.patch`: Mainline tagger backport.
4. `target/linux/generic/backport-6.12/830-02-v6.19-net-dsa-yt921x-Add-support-for-Motorcomm-YT921x.patch`: Mainline driver backport.
5. `target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`: Exact extraction parameters for 2.4 GHz and 5 GHz radios.
6. `target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network`: Userspace interface mapping for `xiaomi,cr8818`.
7. `target/linux/qualcommax/image/ipq50xx.mk`: Target device image build recipe (`DEVICE_DTS_CONFIG := config@mp03.3`).
8. `package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq50xx`: MTD partitions for U-Boot environment (`0:appsblenv` and `bdata`).

### 2.3 Critical Technical Findings from `yangfl`
- **SerDes Role Mismatch & REVSGMII Abuse (`940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`):**
  - **The Problem:** The IPQ5018 Uniphy SerDes operates as a MAC. The Motorcomm YT9215 switch Port 8 SerDes must operate in **PHY role** (`REVSGMII`).
  - However, the Linux kernel lacks a standardized `PHY_INTERFACE_MODE_REVSGMII` enum.
  - In unpatched mainline `drivers/net/dsa/yt921x.c`, `PHY_INTERFACE_MODE_SGMII` configures the switch SerDes as `YT921X_SERDES_MODE_SGMII` (MAC role), resulting in two MACs facing each other and SerDes link failure!
  - **The Solution:** Patch 940 intercepts `PHY_INTERFACE_MODE_SGMII` inside `yt921x_port_config()` and remaps it:
    ```c
    case PHY_INTERFACE_MODE_SGMII:
        /* abuse SGMII for REVSGMII */
        ctrl = YT921X_SERDES_MODE_REVSGMII;
        break;
    ```
  - **Significance for Linux 6.18:** This patch is **mandatory** for our OpenWrt 6.18 build! Without it, Port 8 SGMII link negotiation will fail.
- **Switch Reset Timing:**
  - `ipq5018-cr8818.dts` uses:
    ```dts
    reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
    reset-assert-us = <10000>;  /* 10ms */
    reset-deassert-us = <50000>; /* 50ms */
    ```
- **Wi-Fi Calibration Offsets (Authoritative):**
  - 2.4 GHz (`ath11k/IPQ5018/hw1.0/caldata.bin`): Partition `0:art`, offset **`0x1000`**, length **`0x20000`** (128 KiB).
  - 5 GHz (`ath11k/qcn6122/hw1.0/caldata.bin`): Partition `0:art`, offset **`0x26800`**, length **`0x20000`** (128 KiB).
  - **Zero MAC address patching** is performed in userspace hotplug for `xiaomi,cr8818`.

---

## 3. In-Depth Audit: `zcop/immortalwrt` (Enhanced Switch Driver & Register Telemetry)

### 3.1 Provenance and Scope
- **Source Link:** [`https://github.com/zcop/immortalwrt`](https://github.com/zcop/immortalwrt)
- **Key Artifacts:** `README.yt921x.md`, `tag_yt921x_enhanced.c`, `drivers/net/dsa/yt921x*.{c,h}`, `ipq5018-cr881x.dts`.
- **Validation Scope:** Validated on live CR881x hardware by community developer `zcop`.

### 3.2 Evidence Demarcation Across 3 Capability Levels
To prevent unjustified extrapolation, we strictly distinguish three levels of functionality:

| Level | Capability | Status in `zcop` | Empirical Basis & Audit Evidence |
|---|---|---|---|
| **Level A** | **YT921x DSA Switch Driver** | **`VERIFIED`** | Documented in `README.yt921x.md`. Confirmed 7-port architecture, 5x PHY, 9K jumbo frames, 802.1Q VLAN, storm control, and DWRR egress scheduling. |
| **Level B** | **Dual-Conduit Architecture** | **`VERIFIED`** | Documented in `README.yt921x.md` ("Secondary conduit raw-frame fallback handling"). Uses `tag_yt921x_enhanced.c` to parse `secondary-conduit-user-mask = <0x8>`. |
| **Level C** | **NSS Hardware Offload (NSS-DP & ECM) on CR8818** | **`NSS_NOT_VERIFIED`** | **CRITICAL AUDIT FINDING:** `README.yt921x.md` does **NOT** mention NSS offload, `qca-nss-dp`, or `qca-nss-ecm`. The presence of a functional DSA driver does NOT prove that NSS hardware NAT acceleration operates successfully on CR8818. |

### 3.3 Known Deficiencies & Unfinished Features in `zcop` Driver (`README.yt921x.md`)
1. **Active Queue Management (WRED/RED):** Marked **`UNSUPPORTED / hardware limitation`** (no validated silicon support for probabilistic drop math path).
2. **Buffer Management:** Marked **`TODO`** (tail-drop limit tuning remains pending undocumented `0x34xx` BMU mapping).
3. **ETS/SP Scheduling:** Contention tests still **FAIL** ("Complete ETS/SP scheduling remains open: the experimental priority-group correction removes the false `0x300400` SP-address assumption, but strict/weighted contention tests still fail").
4. **Hardware Egress Flower:** General egress `tc flower` is rejected with `EOPNOTSUPP`.

---

## 4. In-Depth Audit: `kuncy7/openwrt-nss-edma` (Upstream `stmmac` + NSS Data-Plane Hook)

### 4.1 Architecture and Scope
- **Source Link:** [`https://github.com/kuncy7/openwrt-nss-edma`](https://github.com/kuncy7/openwrt-nss-edma)
- **Concept:** Uses upstream `stmmac` / `dwmac-ipq5018` for GMAC control, patched with `kmod-qca-dwmac-nss` to claim the data plane at runtime.
- **DSA Offload Mechanism:** Operates the switch conduit via **`tag_8021q`** (`qca-8021q`, `rtl8365mb-8021q`, `an8855-8021q`).

### 4.2 Objective Re-Evaluation of Kuncy7 for CR8818
Rather than declaring integration "impossible", we classify the technical reality under strict evidence taxonomy:

| Technical Question | Status | Objective Engineering Finding |
|---|---|---|
| Does Kuncy7 support target `xiaomi_cr8818`? | **`VERIFIED_ABSENT`** | Kuncy7 supports `xiaomi_cr8806` (QCA8337 switch), but has zero board definitions or DTS for `xiaomi,cr8818` or Motorcomm switches. |
| Does Kuncy7 support `tag_yt921x` directly? | **`CURRENTLY_INCOMPATIBLE`** | Kuncy's NSS pipeline requires `tag_8021q`. Firmware NSS 12.5 only parses 802.1Q tags or Qualcomm header tags. It has no parser for Motorcomm DSA tags. |
| Can YT9215 be configured in 802.1Q mode? | **`EXPERIMENTAL / UNKNOWN`** | It is theoretically possible to configure YT9215 ports in 802.1Q VLAN trunking mode instead of DSA tagging, but this has **never been developed or validated** for this switch. |
| Could a translation shim be created? | **`THEORETICALLY_POSSIBLE / HIGH_EFFORT`** | A kernel shim translating `tag_yt921x` frames to 802.1Q before passing to NSS is conceptually possible, but would introduce CPU overhead and represents an unverified R&D project. |

### 4.3 Severe Known Issue in Kuncy7 (Release 2026.11.09): NSS 12.5 on 256MB Devices
> [!CAUTION]
> **24/7 Workstation Reliability Risk:**
> Kuncy's official release notes (dated 09/11/2026) document a critical bug on **256 MB RAM devices**:
> - Under high Wi-Fi client packet retransmissions, NSS 12.5 buffer descriptors can be held without timely release.
> - On 256 MB devices (with constrained packet buffer pools), this memory starvation causes **wired Ethernet traffic to completely stall / freeze**.
> - The author explicitly noted that the **256 MB device group was NOT tested** in that release.
> - This directly threatens our Product Owner's mandate for an uninterrupted 24/7 workstation connection.

---

## 5. Comparative Evaluation Summary

| Feature / Dimension | `yangfl/openwrt` (b230c2f) | `zcop/immortalwrt` | `kuncy7/openwrt-nss-edma` |
|---|---|---|---|
| **Target Hardware Focus** | **Xiaomi CR8818 specifically** | Xiaomi CR881x family | Generic IPQ50xx + QCA8337 / RTL8367 |
| **Driver Architecture** | Upstream Linux 6.19 backport | Out-of-tree enhanced driver | Upstream DSA with `tag_8021q` |
| **Switch SerDes Handling** | Patch 940 (REVSGMII abuse) | Enhanced SerDes mode handling | Not applicable (no YT9215) |
| **Tagger Implementation** | Mainline `tag_yt921x.c` | Out-of-tree `tag_yt921x_enhanced.c` | Standard Linux `tag_8021q` |
| **NSS Acceleration** | None (Pure Linux flowtable) | Dual-conduit claimed; **`NSS_NOT_VERIFIED`** | Full NSS offload via `qca-dwmac-nss` |
| **256MB Stability Risk** | **Low** (Zero NSS memory lockup) | **Medium** (Unverified NSS memory impact) | **High** (Documented Ethernet stall on 256M) |
| **Best Architectural Role** | **Core Baseline for Phase 1 (Clean DSA)** | **Register & Feature Reference for YT9215** | **Reference for 256MB Low-Memory Tuning** |
