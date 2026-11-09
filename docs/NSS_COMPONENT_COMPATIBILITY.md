# Qualcomm NSS Component Compatibility & Kernel API Evolution: Xiaomi CR8808 Ver.B (CR8818)

- **Document ID:** `docs/NSS_COMPONENT_COMPATIBILITY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Target OS:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Scope:** Component Audit, Kernel API Evolution (4.4 -> 5.15 -> 6.18), Provenance & Patches
- **Status:** Architectural Research & Compatibility Specification (Phase B Deliverable)

---

## 1. Executive Summary & Audit Methodology

Porting Qualcomm NSS (Network Subsystem) hardware offload to modern Linux kernels cannot be accomplished by blindly copying legacy Qualcomm QSDK drivers.
- **Stock Firmware Baseline:** Xiaomi RA82 Global v1.4.31 runs on **Linux kernel 4.4.60** (32-bit ARMv7 musl), using monolithic, proprietary kernel modules (`qca-ssdk.ko`, `qca-nss-dp.ko`, `qca-nss-drv.ko`, `yt_switch.ko`).
- **Intermediate LTS Target:** Linux kernel 5.15 was the standard in OpenWrt 22.03 / 23.05, where early NSS backports were established for IPQ807x/IPQ6018, but required massive out-of-tree patches.
- **Target Upstream Platform:** OpenWrt mainline runs on **Linux kernel 6.18** (64-bit AArch64 musl), featuring modernized DSA, Phylink, and netfilter subsystems.

This document audits every individual software component, tracks breaking kernel API changes between 4.4, 5.15, and 6.18, and documents exact source locations, commit hashes, and patch dependencies.

---

## 2. Component-by-Component Compatibility Audit

| Component | Stock Xiaomi (Kernel 4.4) | OpenWrt LTS (Kernel 5.15) | OpenWrt Target (Kernel 6.18) | Compatibility Status on 6.18 | Provenance & Source Location |
|---|---|---|---|---|---|
| **NSS Firmware Binary** | `retail_router0.bin` (QSDK 11.4) | `retail_router0.bin` (12.2 / 12.5) | `retail_router0.bin` (NSS 12.5-210) | `SOURCE_VERIFIED` (Binary blob) | `kuncy7/nss-packages/qca-nss-fw-ipq50xx` / Qualcomm QSDK |
| **NSS Core Driver (`qca-nss-drv`)** | Proprietary QSDK 4.4 out-of-tree module | Patched out-of-tree module | Modernized module for 6.18 | `BUILD_VERIFIED` | `kuncy7/nss-packages` (branch `ipq50xx-rebase`) |
| **DWMAC NSS Glue (`qca-dwmac-nss`)** | Not available (used vendor `qca-nss-dp`) | Early prototypes for IPQ50xx | Fully functional `stmmac` data-plane claim module | `BUILD_VERIFIED` | `kuncy7/nss-packages/qca-dwmac-nss` (Julius Bairaktaris / kuncy7) |
| **Legacy Data Plane (`qca-nss-dp`)** | Active (`qca-nss-dp.ko`) | Active on older targets | **SUPERSEDED** by `qca-dwmac-nss` | **NOT RECOMMENDED** (Bypasses upstream `stmmac`) | Qualcomm QSDK / `zcop/immortalwrt` |
| **Connection Manager (`qca-nss-ecm`)** | QSDK ECM for `iptables` | ECM patched for Linux 5.15 | ECM modernized for `nftables` / 6.18 | `BUILD_VERIFIED` | `kuncy7/nss-packages/qca-nss-ecm` |
| **NSS Clients (`qca-nss-clients`)** | PPPoE, VLAN, Bridge, IPsec, Wi-Fi | Partial backports | Modules ported to 6.18 netdev APIs | `BUILD_VERIFIED` | `kuncy7/nss-packages/qca-nss-clients` |
| **Motorcomm Switch Driver (`yt921x.c`)** | Proprietary `yt_switch.ko` | Out-of-tree backports | Mainline kernel 6.19 / backported to 6.18 | `SOURCE_VERIFIED` | Mainline Linux `drivers/net/dsa/yt921x.c` / `yangfl` commit `b230c2f` |
| **Motorcomm Switch Tagger (`tag_yt921x.c`)** | N/A (Driver-internal tagging) | Out-of-tree DSA tagger | Mainline kernel 6.19 / backported to 6.18 | `INCOMPATIBLE_WITH_NSS` (Proprietary tag rejected by NSS) | Mainline Linux `net/dsa/tag_yt921x.c` |
| **DSA 802.1Q Tagger (`tag_8021q.c`)** | Not available in 4.4 | Available in 5.15 | Fully supported in 6.18 core | **`TARGET_INTEGRATION`** (Compatible with NSS parser) | Linux core `net/dsa/tag_8021q.c` |
| **Wi-Fi Driver (`ath11k` / `ath11k_ahb`)** | Vendor `qca-wifi` QSDK driver | Upstream `ath11k` (early) | Upstream `ath11k_ahb` with NSS Wi-Fi offload hooks | `BUILD_VERIFIED` | Linux kernel `drivers/net/wireless/ath/ath11k/` |
| **Wi-Fi Firmware (`qcn6122`)** | Proprietary QSDK binaries | Upstream firmware blobs | `ath11k-firmware-qcn6122` + Q6 WPSS blobs | `SOURCE_VERIFIED` | OpenWrt `package/firmware/ipq-wifi` & Qualcomm |
| **WireGuard Daemon** | `wireguard-go` (High RAM RSS) | `kmod-wireguard` or Go | **`boringtun-cli`** (Rust, AArch64 musl) | `TARGET_INTEGRATION` (Peak RSS < 15 MB) | Cloudflare BoringTun 0.7.1 + local signalfd patch |

---

## 3. Kernel API Evolution & Breaking Changes: 4.4 -> 5.15 -> 6.18

A successful port of NSS to kernel 6.18 requires addressing key Linux kernel API transformations:

### 3.1 Network Subsystem (`sk_buff` and Netdev Operations)
1. **`skb->dev` and Ingress Netdev Handling:**
   - *Kernel 4.4:* `skb->dev` was directly mutable across interrupt handlers without strict RCU read-locks.
   - *Kernel 6.18:* Enforces strict RCU annotations (`rcu_dereference`) and forbids arbitrary reassignment of `skb->dev` without `skb_scrub_packet()` or `dev_hold()`.
   - *Fix in `qca-nss-drv` / `qca-dwmac-nss`:* Descriptors claimed from DWMAC RX rings must properly initialize `skb->protocol` and `skb_set_network_header()` before submitting to NSS or host slow-path.
2. **`net_device_ops.ndo_start_xmit`:**
   - *Kernel 4.4:* Single TX lock per netdev; return codes were raw integers.
   - *Kernel 6.18:* Multi-queue XMIT (`ndo_select_queue`) with `netdev_tx_t` enum returns (`NETDEV_TX_OK`, `NETDEV_TX_BUSY`).
   - *Fix in `qca-dwmac-nss`:* When `qca-dwmac-nss` claims the DWMAC interface, it replaces `netdev->netdev_ops` with a custom structure where `ndo_start_xmit` enqueues packets directly into the NSS NPU TX ring.
3. **NAPI Polling Mechanism:**
   - *Kernel 4.4:* `netif_napi_add()` with static weight.
   - *Kernel 6.18:* `netif_napi_add_weight()` or `netif_threaded_napi_add()`; requires explicit `napi_enable()` / `napi_disable()` synchronization.
   - *Fix:* `qca-dwmac-nss` calls `napi_disable()` on the host `stmmac` NAPI context to prevent host interrupts, while NSS manages its own hardware ring interrupts.

### 3.2 Distributed Switch Architecture (DSA) & Phylink Evolution
1. **Evolution from Legacy Switch Ops to Modern Phylink:**
   - *Kernel 4.4 (QSDK):* Switches were managed via monolithic `switch_dev` / `swconfig` ioctl APIs.
   - *Kernel 5.15:* Introduction of modern DSA, but many drivers retained custom phylink hacks.
   - *Kernel 6.18:* Strict enforcement of **Phylink PCS (Physical Coding Sublayer)** APIs.
   - *Significance for YT9215:* Mainline `yt921x.c` uses `phylink_mac_ops` (`mac_config`, `mac_link_up`, `mac_link_down`). This architecture is fully aligned with Linux 6.18.
2. **DSA Conduit Tagger Architecture:**
   - In Linux 6.18, DSA supports dynamic conduit tagger switching via `net/dsa/tag_8021q.c`.
   - The DSA core provides helper functions:
     ```c
     int dsa_tag_8021q_register(struct dsa_switch *ds, __be16 proto);
     void dsa_tag_8021q_unregister(struct dsa_switch *ds);
     ```
   - Implementing these helpers in `yt921x.c` enables standard 802.1Q tagging on the CPU conduit, which seamlessly integrates with NSS!

### 3.3 Netfilter & Connection Tracking (`qca-nss-ecm`)
1. **Transition from `iptables` to `nftables`:**
   - *Kernel 4.4:* ECM hooked directly into `iptables` PREROUTING and POSTROUTING netfilter hooks.
   - *Kernel 6.18:* Modern OpenWrt uses **`nftables`** exclusively via `firewall4`.
   - *Fix in `kuncy7/nss-packages/qca-nss-ecm`:* ECM has been updated to hook Linux `nf_conntrack` event listeners (`nf_ct_event_register`) rather than raw `iptables` hooks. When a connection state reaches `ESTABLISHED`, ECM constructs the hardware flow rule independently of the firewall frontend.

### 3.4 Memory Management & DMA Allocations
1. **DMA Coherent Memory Allocations (`dma_alloc_coherent`):**
   - *Kernel 4.4:* Permitted large multi-megabyte contiguous memory requests from standard slab.
   - *Kernel 6.18:* Enforces DMA pools (`dma_alloc_coherent`) constrained by device tree reserved-memory nodes and kernel boot parameters.
   - *Fix for 256 MB RAM:*
     - Kernel boot argument: `coherent_pool=512k` (from Kuncy patch 0828).
     - DTS reservation: Restrict `nss_region` to 12 MiB:
       ```dts
       nss_region: nss@40000000 {
           reg = <0x0 0x40000000 0x0 0xc00000>;
           no-map;
       };
       ```

---

## 4. Provenance, Repository Audits, and Patch References

### 4.1 Primary NSS Reference: `kuncy7/openwrt-nss-edma` & `nss-packages`
- **Repository:** [`https://github.com/kuncy7/openwrt-nss-edma`](https://github.com/kuncy7/openwrt-nss-edma)
- **Companion Feed:** [`https://github.com/kuncy7/nss-packages`](https://github.com/kuncy7/nss-packages) (Branch: `ipq50xx-rebase`)
- **Key Artifacts:**
  - `qca-dwmac-nss`: Kernel module implementing `nss-dp` data-plane claim on upstream `stmmac`.
  - `target/linux/qualcommax/patches-6.18/`: Contains kernel compatibility patches for `stmmac`, netfilter, and `ath11k`.
  - `qca-nss-fw-ipq50xx`: Houses `retail_router0.bin` (Qualcomm NSS 12.5-210 firmware binary).

### 4.2 Hardware Baseline Reference: `yangfl/openwrt` (Commit `b230c2f`)
- **Commit:** [`b230c2fbb5548200772a20546bdef17bb50a7d5f`](https://github.com/yangfl/openwrt/commit/b230c2fbb5548200772a20546bdef17bb50a7d5f)
- **Author:** David Yang (`mmyangfl@gmail.com`)
- **Key Artifacts:**
  - `ipq5018-cr8818.dts`: Canonical board DTS for Xiaomi CR8818 with Motorcomm YT9215 at MDIO `0x1d` and QCN6102 Wi-Fi.
  - `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`: Essential patch resolving SerDes MAC/PHY collision on Switch Port 8.
  - `11-ath11k-caldata`: Hotplug script extracting Wi-Fi calibration from `0:art` without userspace MAC patching.

### 4.3 Switch Driver Reference: Mainline Linux 6.19
- **Files:** `drivers/net/dsa/yt921x.c` and `net/dsa/tag_yt921x.c`.
- **Reviewers:** Andrew Lunn, signed off by Jakub Kicinski.
- **Portability:** Backported cleanly to OpenWrt 6.12 (`yangfl`) and 6.18 (`CR8808-CUSTOM-FIRMWARE`).

---

## 5. Reusable Components vs. Required New Engineering

| Subsystem Component | Action | Engineering Scope & Files Affected |
|---|---|---|
| **NSS Core Driver (`qca-nss-drv`)** | **Reuse** | Directly ingest package from `kuncy7/nss-packages;ipq50xx-rebase`. |
| **NSS Firmware Binary (`retail_router0.bin`)** | **Reuse** | Directly ingest package from `kuncy7/nss-packages`. |
| **DWMAC NSS Glue (`qca-dwmac-nss`)** | **Reuse** | Directly ingest package; configure to claim `dp1` and/or `dp2`. |
| **Connection Manager (`qca-nss-ecm`)** | **Reuse** | Directly ingest package; configure with low-memory rule limits. |
| **Board DTS (`ipq5018-cr8818.dts`)** | **Adapt** | Extend `yangfl` DTS with NSS reservation node (`nss_region`) and NSS clocks. |
| **SerDes SGMII Patch (Patch 940)** | **Reuse** | Apply `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`. |
| **Wi-Fi Calibration Script (`11-ath11k-caldata`)** | **Reuse** | Use `yangfl` extraction offsets (`0x1000` / `0x26800`). |
| **Motorcomm Switch Driver (`yt921x.c`)** | **Extend (New Code)** | Implement `tag_8021q` operations (`tag_8021q_vlan_add/del`) in `yt921x.c` (~300 lines of C). |
| **WireGuard Daemon (`boringtun-cli`)** | **Integrate** | Ingest custom BoringTun Rust AArch64 package with `procd` service script. |
