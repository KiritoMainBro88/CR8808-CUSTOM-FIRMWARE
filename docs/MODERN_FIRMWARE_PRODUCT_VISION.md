# Modern CR8818 Firmware Product Vision & Dual-Track Architecture

- **Document ID:** `docs/MODERN_FIRMWARE_PRODUCT_VISION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual Cortex-A53 @ 1.0 GHz, 256MB DDR3L, 128MB SPI NAND, Motorcomm YT9215SC GbE switch, QCN6102 5 GHz Wi-Fi 6)
- **Baseline Benchmark:** Xiaomi RA82 Global Firmware v1.4.31 (Linux 4.4.60 QSDK, 32-bit ARMv7 musl)
- **Author:** Gemini Engineering Team (Implementer / System Operator)
- **Reviewer:** ChatGPT Architecture Lead & Product Owner
- **Status:** Strategic Product Vision & Architectural Baseline

---

## 1. Executive Summary & Core Guiding Principles

The fundamental objective of the `CR8808-CUSTOM-FIRMWARE` project is to transition the Xiaomi CR8808 Ver.B from vendor-locked, obsolete stock software to a modern, secure, and extensible operating environment **without compromising hardware capability, network throughput, or wireless performance**.

### The Core Mandate
Replacing stock firmware (Xiaomi RA82) with a generic, unoptimized OpenWrt build often results in degraded performance: loss of hardware NAT offloading, CPU saturation at gigabit speeds, unstable switch port mapping, or Wi-Fi channel width limitations. Our development follows the principle:
> **Modern OpenWrt + Hardware Acceleration + Memory-Safe Rust Userspace.**

Stock RA82 is treated as an **unforgiving empirical baseline**: any custom image that cannot match RA82's gigabit line-rate throughput, 160 MHz Wi-Fi link speed, or switch stability is rejected for daily deployment.

```
       +-------------------------------------------------------------+
       |             CR8808 Ver.B (CR8818) Target Hardware           |
       |  Qualcomm IPQ5018 (2x A53 @ 1GHz) | 256MB RAM | 128MB NAND   |
       +-------------------------------------------------------------+
                                      |
                     +----------------+----------------+
                     |                                 |
                     v                                 v
        +-------------------------+       +-------------------------+
        |   DAILY DRIVER TRACK    |       |   EXPERIMENTAL TRACK    |
        |  OpenWrt 25.12.6 Stable |       |    Linux 6.18 LTS Git   |
        |  Linux 6.12 LTS Base    |       |   Bleeding-Edge OpenWrt |
        |  Full Hardware Parity   |       |   NSS Forward-Porting   |
        |  Wi-Fi HE160 Verified   |       |   Rust Network Services |
        |  Clean DSA Flowtable    |       |   CAKE / PBR Advanced   |
        |  BoringTun Rust VPN     |       |   PC Build & Test ONLY  |
        +-------------------------+       +-------------------------+
```

---

## 2. Strategic Division: Dual Product Development Tracks

To resolve the tension between software freshness and hardware stability, the firmware is architecturally split into two distinct, parallel tracks:

### 2.1 The Daily Driver Track (Production & Stability First)
- **Target Audience:** Daily home/office router deployment where downtime, packet loss, or wireless glitches are unacceptable.
- **Upstream Base:** OpenWrt 25.12.x Stable Release Series (specifically OpenWrt 25.12.6, Linux Kernel 6.12.112 LTS).
- **Core Kernel:** Linux 6.12.112 LTS (tested, verified OpenWrt target patches, EOL Dec 2028).
- **Package Manager:** `apk` (`apk-tools` v3, Alpine-derived OpenWrt 25.12 package management).
- **Network Datapath:** Clean Linux Distributed Switch Architecture (DSA) using the upstreamed Motorcomm YT9215SC driver (`tag_yt921x.c`) and Linux software flowtable offload (`nftables` / `flow offload`).
- **Heavy Services Quarantine:** SQM/CAKE and AdGuardHome are decoupled and quarantined from default daily inclusion due to CR8808's 256MB RAM and dual Cortex-A53 CPU limits (CAKE near Gigabit saturates dual A53 cores; AdGuardHome requires 60-100MB RAM).
- **Hardware Parity Acceptance Targets:**
  - 1x WAN + 3x LAN independent gigabit addressing.
  - Wi-Fi 6 (802.11ax) on 2.4 GHz (574 Mbps) and 5 GHz with **HE160 160 MHz channel width (2402 Mbps)**.
  - Gigabit line-rate NAT (940+ Mbps) with <60% host CPU utilization under software flowtable (`ACCEPTANCE_TARGET`).
  - Qualcomm NSS offload is strictly excluded from Daily Driver and quarantined in the Experimental track.
- **Userspace Services:**
  - `firewall4` (`nftables` backend).
  - BoringTun Rust (`boringtun-cli 0.7.1` with signalfd and Issue #498 peer update patches) as the userspace WireGuard engine.
  - Modern LuCI web administration with HTTPS/TLS.
  - Failsafe boot and automated configuration rollback.
- **Safety Boundary:** PC build and network namespace verification ONLY. Flash authorization remains strictly `NO-GO` pending independent non-UART recovery validation.

### 2.2 The Experimental Track (Technology & Performance Frontier)
- **Target Audience:** Engineering laboratory, performance benchmarking, and out-of-tree hardware acceleration research.
- **Upstream Base:** OpenWrt Git Mainline / Snapshot development branch.
- **Core Kernel:** Linux 6.18 LTS (kernel.org Long Term Support projected through December 2028).
- **Acceleration Experiments:**
  - Forward-porting out-of-tree Qualcomm NSS modules (`qca-nss-drv`, `qca-nss-dp`, `qca-nss-ecm`) from legacy QSDK 4.4/5.4 to modern 6.18 LTS interfaces.
  - Hardware switchdev offload enhancements on the YT9215SC switch fabric.
- **Userspace Experiments:**
  - Expansion of Rust userspace daemons: lightweight system telemetry daemon, DNS policy routing daemon, dynamic watchdog.
  - Bufferbloat optimization via CAKE SQM at 1 Gbps WAN rates.
- **Safety Boundary:** All experimental builds are built and verified **strictly on PC (WSL2 / Linux network namespaces)**. Flashing to physical flash memory is barred until serial console recovery and U-Boot failsafe mechanisms are 100% operational.

---

## 3. Kernel Version & Upstream Alignment Analysis

### 3.1 Kernel.org LTS vs. OpenWrt Stable Cadence

| Parameter | Linux 6.12 LTS (Daily Driver) | Linux 6.18 LTS (Experimental) | Stock Xiaomi RA82 (Linux 4.4.60) |
|---|---|---|---|
| **Upstream Status** | OpenWrt 25.12.6 Default LTS | Kernel.org Mainline LTS (EOL Dec 2028) | Obsolete Vendor QSDK Fork (EOL 2018) |
| **Maintenance Horizon** | Actively backported by OpenWrt core team | Protected upstream until Dec 2028 | 0 security patches since 2021 |
| **CVE Vulnerability Stance** | High: backported security patches landed weekly | High: direct upstream kernel.org LTS tree | Extreme: 100+ unpatched known kernel CVEs |
| **DSA Subsystem Stability** | High: stable switchdev and phylink APIs | Evolving: MAC PCS and tagger API refactored | N/A (SSDK proprietary character driver) |
| **NSS Porting Feasibility** | Moderate: patch sets available from community | High Effort: API breakages in netfilter hooks | Native vendor blobs pre-integrated |
| **Memory Footprint** | ~182 MB usable out of 256MB DDR3L | ~180 MB usable out of 256MB DDR3L | ~110 MB free RAM |

### 3.2 Technical Justification: Why Not Blindly Jump to 6.18 for Daily Driver?
1. **Driver Interface Breakages:** As proven in our Milestone M4 audit, newer Linux kernels refactor internal networking abstractions:
   - `drivers/net/ethernet/stmicro/stmmac/dwmac-ipq5018.c` fails on 6.18 because `linux/pcs/pcs.h` was reorganized.
   - DSA switch operations (`struct dsa_switch_ops`) in 6.6+ removed legacy multicast routing hooks (`.port_mrouter`) and altered `.port_policer_add` signatures.
   - Qualcomm NSS modules hook directly into internal `sk_buff` recycling and `nf_flow_table` structs, which experience internal ABI breakage between LTS generations.
2. **Security is Maintenance, Not Just Version Numbers:** OpenWrt 25.12.6 on Linux 6.12 receives continuous, targeted vulnerability patches for embedded daemons (`uhttpd`, `dnsmasq`, `odhcpd`, `dropbear`). Running Linux 6.18 with unmaintained or hackily-patched drivers creates greater operational vulnerability than running a fully-tested 6.12 LTS image.

---

## 4. Hardware Parity Gates & Acceptance Criteria

Firmware cannot transition from Experimental to Daily Driver without passing every hardware parity gate:

1. **Wi-Fi 6 HE160 Parity Gate:** 
   - 5 GHz QCN6102 must establish 160 MHz channel width (MCS 0-11, 2x2 MIMO) achieving 2402 Mbps theoretical PHY rate and >1.2 Gbps real over-the-air TCP iperf3 throughput.
2. **Switch Fabric Parity Gate:** 
   - Motorcomm YT9215SC DSA driver must independently address 1 WAN and 3 LAN physical ports without bridging loops, packet leakage, or MDIO timeout panics.
3. **Throughput & CPU Utilization Gate:**
   - 1000BASE-T line rate (940+ Mbps) bi-directional traffic must sustain with <60% host CPU load under software flowtable, and <15% under NSS acceleration.
4. **Memory Stability Gate:**
   - On CR8818's 256MB physical RAM, total idle resident memory must not exceed 90 MB, leaving >90 MB available for buffers, connection tracking, and VPN workloads.
5. **VPN Runtime Gate:**
   - BoringTun Rust daemon must execute with <15 MB VmRSS under 1 Gbps continuous traffic, with zero memory leaks over 24-hour soak tests.

---

## 5. Architectural Summary Table

```
+--------------------------+------------------------------+------------------------------+
| Dimension                | Daily Driver Track           | Experimental Track           |
+--------------------------+------------------------------+------------------------------+
| Release Target           | OpenWrt 25.12.6 Stable       | OpenWrt Git Master Snapshot  |
| Kernel Version           | Linux 6.12.112 LTS (EOL 2028)| Linux 6.18 LTS (EOL 2028)    |
| Package Manager          | apk (apk-tools v3)           | apk (apk-tools v3)           |
| DSA Driver               | Clean YT9215SC DSA (upstream)| Enhanced Switchdev YT9215SC  |
| Offload Architecture     | Software Flowtable (nftables)| Qualcomm NSS Acceleration    |
| Wi-Fi Stack              | ath11k (upstream mac80211)   | ath11k + NSS Wi-Fi Offload   |
| Wi-Fi 5GHz Link Rate     | HE160 2402 Mbps Verified     | HE160 2402 Mbps Verified     |
| VPN Subsystem            | BoringTun Rust (musl static) | BoringTun Rust + eBPF Tun    |
| Quality of Service       | Standard FQ-CoDel            | CAKE SQM (Quarantined)       |
| Host Memory Profile      | ESTIMATE: 140-150MB free     | ESTIMATE: ~120MB free        |
| NAT Throughput Target    | ACCEPTANCE_TARGET: 940+ Mbps | ACCEPTANCE_TARGET: Line-rate |
| Deployment Status        | PC Build Complete (NO-GO)    | PC Build & Namespaces ONLY   |
+--------------------------+------------------------------+------------------------------+
```
