# 03 — Initial System Architecture

Status: Candidate architecture. No base platform approved.

## Architectural principles
- Exact hardware compatibility before kernel-version preference.
- Keep upstream repositories separate and pin exact commits.
- Integrate small patches with provenance.
- Build and inspect on PC before device interaction.
- Preserve stock firmware as baseline.
- Measure before tuning.
- Do not infer Xiaomi proprietary feature parity.

## Candidate source roles
- zcop ImmortalWrt: candidate CR881x board/DTS and YT921x switch reference.
- kuncy7 OpenWrt NSS EDMA: NSS/ECM/ath11k/qdisc reference.
- kuncy7 NSS packages: NSS driver/package reference.
- OpenWrt upstream: kernel/networking/package foundation.
- ImmortalWrt upstream: distribution/package alternative.
- fanha99 CR8806 NSS: CR8806 porting reference only.
- hzyitc Redmi AX3000: legacy IPQ50xx/QSDK reference.
- marchmin zcop fork: YT9215 register reference.

These are candidates, not confirmed compatible sources.

## Base platform decision
Compare kernel/API, DTS, GPIO/reset/power sequencing, MDIO, switch DSA, Ethernet MAC/EDMA, NSS firmware ABI, ECM, qdiscs, ath11k/mac80211 integration, package ecosystem, memory footprint, security cadence and board-specific changes.

Do not blindly merge zcop and kuncy7. A possible architecture is to use the closest proven CR881x hardware base and selectively port NSS components, but this remains a hypothesis until source audit and tests.

## Integration repository model
This repository owns:
- source manifest and locked revisions;
- device target configuration;
- project-owned patches;
- package/service integration;
- test plans and scripts;
- release manifests and documentation.

Upstream source checkouts should be separate worktrees or source cache, not copied wholesale into the product repository.

## WireGuard target architecture
Target end state: BoringTun Rust only.
Migration order:
1. Package Rust daemon and service on PC.
2. Validate build/link dependencies and UAPI behavior.
3. Later, after explicit router test authorization, use an isolated interface/port.
4. Validate real peer handshake, bidirectional traffic, DNS, MTU, reconnect, restart, CPU/RSS, latency and soak.
5. Validate boot ordering and firewall.
6. Approve Rust as primary.
7. Remove Go service only after all acceptance criteria pass and rollback is available.

## Wi-Fi architecture
Preserve 5 GHz HE160. Verify radio, driver, firmware, board data/calibration, antenna chains and regulatory domain. Test OFDMA/MU-MIMO only where the driver has documented support and client interoperability is confirmed.

## Performance architecture
Track CPU per core, softirq, NSS counters, throughput, loaded latency percentiles, packet loss, RAM pressure, slab, OOM/allocstall, temperature, Wi-Fi retries/airtime and WireGuard resources. No blanket sysctl/RPS/RFS/IRQ/backlog changes without measurement.


## Hybrid Language Architecture (C + Rust + DTS)

Refer to [`docs/RUST_ARCHITECTURE.md`](RUST_ARCHITECTURE.md) for the complete architectural strategy.

```mermaid
graph TD
    subgraph Userspace ["Userspace Subsystems (Rust & Shell)"]
        BORINGTUN["BoringTun Rust Daemon (boringtun-cli)<br/>*Sole WireGuard Engine (AArch64 musl static, 1.4 MB)*<br/>*ChaCha20-Poly1305 (ARM NEON)*"]
        WG_TOOLS["wireguard-tools (wg / wg-quick)"]
        MONITOR["cr8818-monitor System Daemon (Rust)<br/>*Telemetry, Watchdog & Recovery*"]
        NETIFD["netifd (OpenWrt Network Daemon)"]
        PROCD["procd (Init & Process Supervisor)"]
    end

    subgraph Kernel ["Linux Kernel 6.18 Subsystems (C)"]
        TUN["Virtual TUN Driver (/dev/net/tun)"]
        NETFILTER["Netfilter / nftables Firewall"]
        ECM["Qualcomm ECM (Flow Acceleration Engine)"]
        NSS_DRV["Qualcomm NSS Drivers (qca-nss-drv / qca-nss-dp)"]
        DSA_CORE["Linux DSA Core (Distributed Switch Architecture)"]
        YT921X["Motorcomm YT9215SC Driver (yt921x_8021q.c)"]
        DWMAC["Synopsys DWMAC (dwmac-ipq5018.c)"]
        ATH11K["ath11k Wi-Fi Driver (mac80211)"]
    end

    subgraph Hardware ["Hardware Description & Silicon (DTS & Silicon)"]
        DTS["Device Tree (ipq5018-cr8818.dts / ipq5018-cr881x-nss.dts)"]
        SOC["Qualcomm IPQ5018 (Dual Cortex-A53 @ 1.0 GHz)"]
        NPU["Qualcomm NSS NPU Engine (@ 1.0 GHz)"]
        SWITCH["Motorcomm YT9215SC 5-Port Switch (MDIO 0x00)"]
        WIFI_SILICON["QCN6102 5 GHz (HE160) + IPQ5018 2.4 GHz"]
    end

    BORINGTUN <-->|"/var/run/wireguard/wg0.sock (UAPI)"| WG_TOOLS
    PROCD -->|Supervises (auto-respawn)| BORINGTUN
    PROCD -->|Supervises| MONITOR
    NETIFD -->|Configures IP & Routing| TUN
    BORINGTUN <-->|Plaintext Packets| TUN
    TUN <--> NETFILTER
    NETFILTER <--> ECM
    ECM <--> NSS_DRV
    NSS_DRV <--> NPU
    NETFILTER <--> DSA_CORE
    DSA_CORE <--> YT921X
    DSA_CORE <--> DWMAC
    DWMAC <--> SWITCH
    DTS -.->|Configures Pinmux & Clocks| SOC
    DTS -.->|Declares Ports & MDIO| SWITCH
    ATH11K <--> WIFI_SILICON
```
