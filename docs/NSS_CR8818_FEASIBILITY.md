# Qualcomm NSS Hardware Offload Feasibility Analysis: Xiaomi CR8808 Ver.B (CR8818)

- **Document ID:** `docs/NSS_CR8818_FEASIBILITY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Target OS:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Scope:** Technical Feasibility Assessment & Go/No-Go Decision Criteria for NSS Offload Porting
- **Status:** Architectural Research & Engineering Evaluation (Phase B Deliverable)

---

## 1. Executive Summary & Problem Formulation

The Xiaomi CR8808 Ver.B router presents a unique architectural combination in the OpenWrt ecosystem:
- **SoC:** Qualcomm IPQ5018 (dual-core Cortex-A53 @ 1.0 GHz with integrated 1.0 GHz NSS NPU core).
- **Physical RAM:** 256 MB DDR3L (~182 MB usable by Linux kernel).
- **Ethernet Switch:** Motorcomm YT9215SC 7-port switch at MDIO `0x1d` (4 user ports: 3x LAN + 1x WAN, 2x CPU conduits).
- **Wi-Fi Subsystem:** 2.4 GHz 2x2 802.11ax integrated radio + 5 GHz 2x2 802.11ax HE160 QCN6102 companion radio.

### The Core Architectural Dilemma
In modern OpenWrt development:
1. **Upstream OpenWrt (`qualcommax/ipq50xx`):** Operates on clean mainline Linux (kernel 6.12/6.18) with upstream `stmmac` (`dwmac-ipq5018`) and Linux DSA switch drivers. In this mode, **NSS is completely bypassed**, routing is handled by Linux in-kernel software flowtables (`nftables flow_offload`), and CPU utilization at 1 Gbps reaches 50–65%.
2. **Community NSS Trees (`kuncy7/openwrt-nss-edma`):** Have successfully backported Qualcomm NSS offload to Linux 6.18 for IPQ5018 using upstream `stmmac` + `qca-dwmac-nss` + `tag_8021q`. However, all supported devices use Qualcomm QCA8337, Realtek RTL8367, or Airoha AN8855 switches. **Kuncy7 contains zero board support or images for CR8818**.
3. **YT921x Community Trees (`zcop/immortalwrt`):** Successfully run the Motorcomm YT9215 switch under DSA using a proprietary tagger (`tag_yt921x_enhanced.c`), but NSS offload on CR8818 is **`NSS_NOT_VERIFIED`** and undocumented in `README.yt921x.md`.

This document performs an exhaustive, component-level feasibility analysis to answer whether and how Qualcomm NSS Hardware Offload can be ported to the CR8818 on Linux 6.18 without sacrificing stability or exhausting 256 MB RAM.

---

## 2. Definitive Answers to the Three Core Evaluation Questions

### Question 1: Does IPQ5018 have NSS working on Linux Kernel 6.18?
- **Verdict:** **YES (`SOURCE_VERIFIED` & `BUILD_VERIFIED`).**
- **Evidence:**
  1. The `kuncy7/openwrt-nss-edma` repository and its companion package feed `kuncy7/nss-packages` (branch `ipq50xx-rebase`) have successfully compiled and deployed NSS 12.5 hardware offload on Linux kernel 6.18.
  2. Public OpenWrt Forum developer thread **#253014** (*"IPQ5018: NSS offload on kernel 6.18 with the upstream ethernet stack (GL-B3000)"*) demonstrates wire-speed IPv4 NAT (>900 Mbps) with host CPU utilization remaining >90% idle.
  3. The key architectural breakthrough is **`qca-dwmac-nss`**, a shim driver authored by community developers (Julius Bairaktaris, kuncy7) that intercepts upstream `stmmac` (`dwmac-ipq5018`) and implements the `nss-dp` data-plane API without requiring Qualcomm's legacy out-of-tree `qca-nss-dp` or `qca-ssdk` drivers.

### Question 2: Can NSS run together with the Motorcomm YT9215SC DSA Switch?
- **Verdict:** **CONDITIONALLY YES — But STRICTLY INCOMPATIBLE Out-of-the-Box (`INCOMPATIBLE_WITHOUT_ADAPTER`).**
- **Root Cause of Incompatibility:**
  - The closed-source Qualcomm NSS firmware binary (`retail_router0.bin`) parses L2/L3 headers in hardware. It understands standard Ethernet II, IEEE 802.1Q VLAN (`0x8100`), IEEE 802.1ad QinQ (`0x88a8`), PPPoE (`0x8864`), IPv4, and IPv6.
  - The NSS firmware contains **zero parser logic** for Motorcomm's proprietary 8-byte DSA tag (`tag_yt921x.c` / `tag_yt921x_enhanced.c`).
  - Passing frames with `tag_yt921x` headers directly to NSS causes hardware packet classification failures (packet drops or fallbacks to CPU).
- **Engineering Solutions Required:**
  - **Solution A (`tag_8021q` Porting):** Implement `tag_8021q` operations in `drivers/net/dsa/yt921x.c` so the switch uses standard 802.1Q VLAN IDs to represent CPU switch ports instead of proprietary tags.
  - **Solution B (Physical Dual-Conduit Demux):** Exploit the fact that CR8818 has two independent MACs: configure MAC0 (Internal GE PHY -> Port 4) as an untagged, dedicated WAN conduit, and MAC1 (SGMII -> Port 8) for LAN. NSS can offload WAN-to-LAN NAT without proprietary tags on the WAN interface.

### Question 3: Can performance and RAM stability be maintained on a 256 MB device?
- **Verdict:** **YES, with Strict Low-Memory Engineering (`FEASIBLE_WITH_CONSTRAINTS`).**
- **Evidence & Parameters:**
  - Usable physical RAM on CR8818 is ~182 MB (due to U-Boot and TrustZone reservations).
  - Standard NSS profiles allocate 24–32 MiB for packet buffers and large 1024-descriptor ring buffers for Wi-Fi, triggering Out-Of-Memory (OOM) under burst traffic on 256 MB devices.
  - Applying Kuncy's proven 256 MB profile:
    - `ATH11K_MEM_PROFILE_256M=y` (reduces Wi-Fi DMA rings from 1024 to 256/512 descriptors, saving ~18 MiB).
    - `NSS_MEM_PROFILE_LOW=y` (restricts `qca-nss-pbuf` to ~12 MiB).
    - `coherent_pool=512k` (prevents low-memory exhaustion).
    - `vm.min_free_kbytes=8192` (reserves 8 MiB atomic memory for network NAPI handlers).
    - Replacing `wireguard-go` with **BoringTun Rust** (peak RSS < 15 MB).
  - Total resident RAM with all services active is estimated at ~140–150 MiB, leaving 32–42 MiB free buffer headroom.

---

## 3. Comprehensive Feasibility Classification Matrix

Each subsystem and porting task is categorized according to our empirical taxonomy:

| Subsystem / Task | Feasibility Status | Difficulty / Effort | Technical Rationale & Prerequisites |
|---|---|---|---|
| **IPQ5018 SoC NSS Core on Linux 6.18** | `SOURCE_VERIFIED` / `BUILD_VERIFIED` | Medium | Proven in `kuncy7` and OpenWrt thread 253014. Packages `qca-nss-drv`, `retail_router0.bin`, and kernel glue exist. |
| **Upstream Ethernet MAC (`stmmac` / `dwmac-ipq5018`)** | `SOURCE_VERIFIED` | Low | In-tree mainline Linux driver. Fully functional on CR8818 (`yangfl` commit `b230c2f`). |
| **NSS Data-Plane Glue (`qca-dwmac-nss`)** | `SOURCE_VERIFIED` | Medium | In `kuncy7/nss-packages`. Claims `stmmac` netdev and hooks `ndo_start_xmit` to NSS ring buffers. |
| **YT9215SC Switch via Clean DSA (`tag_yt921x`)** | `SOURCE_VERIFIED` | Low | Upstream-derived driver in mainline 6.19 / backported to 6.12/6.18. Single conduit SGMII 1000M verified. |
| **YT9215SC + NSS via Proprietary `tag_yt921x`** | **`INCOMPATIBLE`** | N/A | NSS firmware cannot parse proprietary Motorcomm 8-byte tag. Frames will drop or fail HW classification. |
| **YT9215SC + NSS via `tag_8021q` (VLAN Tagger)** | **`FEASIBLE_REQUIRES_R&D`** | High | Requires implementing `dsa_tag_8021q_ops` in `yt921x.c` using the switch's 802.1Q hardware VLAN engine. |
| **YT9215SC + NSS via Dual-Conduit Demux** | **`FEASIBLE_REQUIRES_DTS`** | Medium | Map MAC0 (Port 4) as untagged WAN and MAC1 (Port 8) as LAN. Avoids rewriting switch tagger for WAN NAT. |
| **Qualcomm ECM Flow Acceleration (`qca-nss-ecm`)** | `BUILD_VERIFIED` | Medium | Hooks Linux netfilter connection tracking and programs 5-tuple hardware flow rules into NSS. |
| **Wi-Fi Subsystem (`ath11k` + QCN6102 HE160)** | `SOURCE_VERIFIED` | Medium | Requires `ath11k-firmware-qcn6122`, calibration extraction from `0:art`, and `ATH11K_MEM_PROFILE_256M`. |
| **256 MB RAM Budget & Stability** | `FEASIBLE_WITH_CONSTRAINTS` | Medium | Requires strict adherence to low-memory profile (`coherent_pool=512k`, `min_free_kbytes=8192`). |
| **WireGuard Rust (BoringTun) Coexistence** | `FEASIBLE` | Low | Userspace tunnel runs concurrently. Outer UDP transport is NSS-accelerated; inner crypto is CPU-handled. |
| **Physical Flashing / Deployment** | **`STRICT_NO_GO`** | Critical | Permanent project safety constraint pending independent recovery validation. |

---

## 4. Deep-Dive: The Switch Tagging Incompatibility Problem

### 4.1 Anatomy of the Frame Collision
When a frame traverses a standard DSA switch:
```
Standard Untagged Ethernet Frame:
[ DMAC (6B) | SMAC (6B) | EtherType (2B) | Payload (46-1500B) | FCS (4B) ]

Frame with Motorcomm Proprietary DSA Tag (tag_yt921x.c):
[ DMAC (6B) | SMAC (6B) | Tag EtherType (0x88f7, 2B) | Tag Header (6B) | Orig EtherType (2B) | Payload ... ]
```
When this packet arrives at the IPQ5018 Synopsys DWMAC receiver:
1. `stmmac` receives the packet from the DMA descriptor ring.
2. If `qca-dwmac-nss` is hooked, the packet is forwarded directly to the NSS firmware input ring.
3. The NSS firmware hardware parser inspects bytes 12–13:
   - Expected: `0x0800` (IPv4) or `0x86dd` (IPv6) or `0x8100` (802.1Q VLAN).
   - Actual: `0x88f7` (Motorcomm Tag).
4. Because `0x88f7` is an unrecognized protocol, the NSS hardware classifier:
   - **Does NOT create an ECM acceleration entry.**
   - Either drops the frame or punts it to the host CPU via an exception path.
   - Result: 0% hardware acceleration, high packet drop rates, and kernel log spam.

### 4.2 Why `tag_8021q` Solves the Collision
The Linux kernel DSA subsystem includes a universal tagging driver: `net/dsa/tag_8021q.c`.
Instead of injecting proprietary bytes, `tag_8021q` uses a standard IEEE 802.1Q VLAN tag:
```
Frame with DSA tag_8021q:
[ DMAC (6B) | SMAC (6B) | TPID (0x8100, 2B) | TCI / VID (2B) | Orig EtherType (2B) | Payload ... ]
```
- In `tag_8021q`, the 12-bit VLAN ID encodes the source switch port:
  `VID = base_vid + port_id` (e.g. VID 100 = LAN1, VID 101 = LAN2, VID 102 = LAN3, VID 103 = WAN).
- When this frame enters the NSS firmware:
  - Bytes 12–13 are `0x8100` (Standard 802.1Q).
  - NSS firmware extracts the VLAN ID, peels the tag, and parses the underlying IPv4/IPv6 packet natively!
  - ECM installs a hardware flow rule mapping the connection to the appropriate VLAN sub-interface.
  - The frame is forwarded at 1 Gbps wire speed by the NSS NPU!

---

## 5. Architectural Solutions for CR8818 NSS Integration

### Strategy 1: The Upstream Mainline Solution (`tag_8021q` Driver Extension)
To make Motorcomm YT9215 compatible with NSS in the same elegant way Kuncy7 supports QCA8337, RTL8367, and AN8855, we must implement `tag_8021q` support in the Motorcomm DSA driver:
1. **Target File:** `drivers/net/dsa/yt921x.c`.
2. **Required Implementation:**
   - Implement `dsa_switch_ops.tag_8021q_vlan_add` and `dsa_switch_ops.tag_8021q_vlan_del`.
   - Program the YT9215 switch's internal 4K VLAN table (`YT921X_VLAN_TABLE_ADDR`) to configure egress tagging on the CPU port (Port 8) and untagged egress on user ports (Ports 0–3).
   - Set the default conduit tagger in `ipq5018-cr8818.dts`:
     ```dts
     &dp2 {
         dsa,tag-protocol = "tag_8021q";
     };
     ```
3. **Feasibility:** **HIGH.** The YT9215 silicon contains a full hardware 802.1Q VLAN engine. This requires ~250–350 lines of C code in `yt921x.c`.

### Strategy 2: The Hardware Topology Bypass Solution (Dual-Conduit Physical Demux)
If writing a full `tag_8021q` driver is deferred, we can exploit the physical board layout of the CR8818:
- **Physical Reality:**
  - GMAC0 (`&dp1`) connects via internal GE PHY to Switch Port 4 (PHY 4).
  - GMAC1 (`&dp2`) connects via SGMII SerDes to Switch Port 8.
- **Implementation:**
  - Configure the switch hardware so that Port 3 (WAN) is isolated and hard-bridged in hardware directly to Port 4 (GMAC0), **without any DSA tags** (`untagged`).
  - Configure Ports 0, 1, 2 (LAN) to communicate over Port 8 (GMAC1).
  - In Linux:
    - `eth0` (`&dp1`) becomes the pure physical WAN netdev (100% untagged Ethernet).
    - `qca-dwmac-nss` claims `eth0` as an accelerated WAN port.
    - ECM offloads flows between `eth0` (WAN) and `br-lan` (LAN).
- **Feasibility:** **MEDIUM.** Can be achieved primarily via DTS and switch initialization registers, but reduces flexibility for per-port LAN VLAN tagging.

---

## 6. Risk Assessment & Engineering Gates

| Risk Category | Hazard Description | Severity | Mitigation Strategy |
|---|---|---|---|
| **Memory Exhaustion (OOM)** | NSS buffer pools + Wi-Fi rings trigger kernel panic under load on 256 MB RAM. | High | Enforce `ATH11K_MEM_PROFILE_256M`, `NSS_MEM_PROFILE_LOW`, `coherent_pool=512k`, `min_free_kbytes=8192`. |
| **Wi-Fi Buffer Leak (Release 2026.11.09)** | User-reported NSS 12.5 buffer stall during heavy Wi-Fi retransmission freezing Ethernet. | High | Maintain Clean DSA baseline as fallback. Conduct multi-hour Wi-Fi retransmission stress tests before deployment. |
| **Switch Register Contention** | SGMII link training fails on Port 8 if reset timings are incorrect. | Medium | Apply `yangfl` patch 940 (REVSGMII abuse) and enforce active-low GPIO 39 reset delays (50ms/250ms). |
| **Flash Wear / Brick Hazard** | Writing unverified firmware images to SPI NAND. | Fatal | Permanent strict **`NO-GO on flashing pending independent recovery validation`**. All tests restricted to local PC build. |

---

## 7. Architecture Go / No-Go Verdict

### Definitive Recommendation:
1. **Phase 1 Baseline:** Remain committed to **Clean DSA Baseline (Architecture Proposal Under Review)** without NSS. This ensures immediate, deterministic, and 100% open-source stability for everyday workstation operation.
2. **Phase 2 NSS Porting:** Formally approve NSS Porting as an **Experimental Research Track**.
   - **Recommended Implementation Path:** **Strategy 1 (`yt921x_8021q`)** because it delivers standard, maintainable OpenWrt architecture identical to QCA8337/RTL8367.
   - **Branch:** Work on dedicated branch `feature/nss-cr8818-port`.
   - **Verification Requirement:** All builds must compile cleanly on PC without requiring physical router flashes.
