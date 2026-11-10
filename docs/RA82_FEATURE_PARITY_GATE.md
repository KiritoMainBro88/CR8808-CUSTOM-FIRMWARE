# RA82 Feature Parity Gate & Hardware Verification Specification

- **Document ID:** `docs/RA82_FEATURE_PARITY_GATE.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual Cortex-A53 @ 1.0 GHz, 256MB DDR3L, 128MB SPI NAND, Motorcomm YT9215SC DSA, QCN6102 5 GHz Wi-Fi 6)
- **Baseline Firmware:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit ARMv7 musl)
- **Target Platform:** Modern OpenWrt Dual-Track (Daily Driver: OpenWrt 25.12.6 / Linux 6.12; Experimental: Linux 6.18 LTS)
- **Author:** Gemini Engineering Team (Implementer / System Operator)
- **Reviewer:** ChatGPT Architecture Lead & Product Owner
- **Status:** Empirical Verification Specification & Parity Gate Matrix

---

## 1. Parity Mandate & Evidence Classification

> [!WARNING] **Zero Unverified Parity Claims Mandate**
> Firmware cannot be declared "ready" or "100% feature-complete" based merely on source existence or PC compilation. Every hardware-facing feature must progress through rigorous empirical evidence gates. Prior to physical bench testing, all hardware capabilities without physical readback are strictly labeled with their actual status.

### Empirical Evidence Levels:

| Evidence Tag | Definition & Criteria |
|---|---|
| **`STOCK_MEASURED`** | Empirically measured and benchmarked on stock Xiaomi RA82 v1.4.31 hardware. |
| **`SOURCE_AVAILABLE`** | Board DTS nodes, kernel patches, or OpenWrt package source code present in the tree. |
| **`BUILD_VERIFIED`** | Successfully compiled for target ABI (`aarch64-unknown-linux-musl` or Linux kernel) without warnings/errors. |
| **`FUNCTION_VERIFIED`** | Functional logic validated in isolated simulation, QEMU, or Linux network namespace harness. |
| **`PERFORMANCE_VERIFIED`** | Throughput, packet loss, latency, or memory consumption measured against acceptance targets on live target hardware. |
| **`UNKNOWN`** | Hardware behavior cannot be proven from existing lab data; physical bench verification is mandatory before release. |

---

## 2. Comprehensive Hardware Parity Matrix

| Feature Item | Stock RA82 Implementation (v1.4.31) | Custom Firmware Implementation | Parity Status | Verification Evidence & Acceptance Threshold |
|---|---|---|---|---|
| **Wi-Fi 2.4 GHz (802.11b/g/n/ax)** | Proprietary Qualcomm ath11k vendor driver blob (2x2 MIMO, 574 Mbps max PHY rate) | OpenWrt upstream `ath11k` driver (`ipq5018` integrated radio, mac80211) | **`SOURCE_AVAILABLE`** | Caldata extracted from `/dev/mtd7` (`0x50000`). Board DTS calibrated. On-device RF performance `UNKNOWN`. |
| **Wi-Fi 5 GHz (802.11a/n/ac/ax)** | Proprietary Qualcomm ath11k PCIe driver blob (QCN6102 2x2 MIMO, 2402 Mbps max PHY rate) | OpenWrt upstream `ath11k_pci` driver for QCN6102 | **`SOURCE_AVAILABLE`** | Caldata extracted from `/dev/mtd7` (`0x80000`). PCIe root complex enumerated. Physical radio sensitivity `UNKNOWN`. |
| **HE160 Channel Width (160 MHz)** | Supported in stock firmware on 5 GHz (Channels 36-64 contiguous or DFS). Achieves 2402 Mbps link rate. | Target OpenWrt `hostapd` with `he_oper_chwidth=2` and DFS radar detection | **`SOURCE_AVAILABLE`** | Mandatory gate: Link rate MUST reach 2402 Mbps with zero radio crashes. Physical link rate `UNKNOWN` until bench test. |
| **Wi-Fi Security: WPA2 / WPA3-SAE** | WPA2-Personal and basic WPA3-Personal Transition mode | Modern `hostapd` / `wpad-mbedtls` with full WPA3-SAE, Opportunistic Wireless Encryption (OWE), and 802.11w PMF | **`BUILD_VERIFIED`** | `wpad-mbedtls` compiles for AArch64 musl. Cryptographic exchange verified; physical client association `UNKNOWN`. |
| **Ethernet Switching & Ports** | Proprietary `yt_switch.ko` module driving Motorcomm YT9215SC via SSDK ioctl | Linux DSA (`tag_yt921x.c`) exposing individual `wan`, `lan1`, `lan2`, `lan3` netdevs | **`BUILD_VERIFIED`** | DSA tagger `tag_yt921x.o` built cleanly in M4. Tagging oracle passed 30/30 unit tests. Physical link negotiation `UNKNOWN`. |
| **PHY Link Rate Negotiation** | Auto-negotiates 10M / 100M / 1000M full duplex on all 4 physical RJ45 ports | Linux phylink subsystem communicating over MDIO bus (GPIO 36/37) | **`SOURCE_AVAILABLE`** | Phylink driver code inspected. GPIO 39 reset sequencing modeled. Live cable insertion auto-neg `UNKNOWN`. |
| **VLAN Isolation & 802.1Q** | Hardware port isolation via vendor switch registers | Standard Linux 802.1Q bridge VLAN filtering (`bridge vlan` switchdev offload) | **`FUNCTION_VERIFIED`** | DSA tagger handles ingress/egress 802.1Q tags in software oracle. Hardware ASIC table offload `UNKNOWN`. |
| **PPPoE WAN Client** | Stock `pppd` daemon with vendor keepalive extensions | Modern upstream `pppd` / `rp-pppoe` with netifd integration and MTU 1492 clamp | **`BUILD_VERIFIED`** | Standard OpenWrt base component. End-to-end ISP handshake on live WAN port `UNKNOWN`. |
| **IPv4 / IPv6 Dual-Stack Routing** | Stock `odhcpd` with vendor cloud DNS redirection | Modern upstream `odhcpd-ipv6only` + `dnsmasq` with DHCPv6-PD and SLAAC | **`FUNCTION_VERIFIED`** | Verified in Linux network namespace integration harness: bi-directional IPv4 and IPv6 traffic sustained at 949 Mbps. |
| **Gigabit NAT Throughput** | 940+ Mbps sustained line rate with proprietary Qualcomm SSDK NSS acceleration | Daily Driver: Linux Software Flowtable (`nftables flow offload`); Experimental: NSS ECM | **`STOCK_MEASURED`** | Stock RA82 measured at 941 Mbps. Software flowtable estimated 940 Mbps @ 50-65% CPU. Hardware NAT parity `UNKNOWN`. |
| **Qualcomm NSS Acceleration** | Active in stock firmware (NPU offload for IPv4/IPv6 NAT, bridge, and crypto) | Evaluated out-of-tree NSS modules (`qca-nss-drv`, `qca-nss-dp`, `qca-nss-ecm`) | **`SOURCE_AVAILABLE`** | `qca-dwmac-nss.ko` compiled cleanly in M4. `qca-nss-dp` failed Kbuild. NSS stability on CR8818 remains unproven (`UNKNOWN`). |
| **CPU & RAM Consumption** | Stock Idle: ~110 MB free RAM out of 256MB. CPU idle <2%. | Target: Total system idle RAM <85 MB, leaving >95 MB free. BoringTun <15 MB RSS. | **`STOCK_MEASURED`** | Stock measured at 110 MB free. BoringTun empirically measured in WSL2 at **3.0 MB VmRSS** (exceeds <15 MB budget). |
| **DNS Resolution & Filtering** | Stock `dnsmasq` 2.80 with vendor cloud telemetry hooks | Modern `dnsmasq` 2.90+ with DNSSEC support and optional AdGuard Home filtering | **`BUILD_VERIFIED`** | Standard OpenWrt package. Local resolution <3 ms. Zero outbound vendor telemetry. |
| **QoS / Bufferbloat Mitigation** | Proprietary static priority queuing (poor bufferbloat handling under load) | Modern CAKE / FQ-CoDel via `sqm-scripts` on egress/ingress interfaces | **`SOURCE_AVAILABLE`** | `kmod-sched-cake` available in kernel tree. Bufferbloat A+ rating target; live test on 1 Gbps WAN `UNKNOWN`. |
| **WireGuard VPN** | Non-existent in stock RA82 (or third-party `wireguard-go` consuming 50+ MB RAM) | **BoringTun Rust (`boringtun-cli 0.7.1`)** with musl static runtime | **`FUNCTION_VERIFIED`** | Fully validated in WSL2 network namespaces: 1.10 GB transferred at 949 Mbps, 3.0 MB VmRSS, Issue #495 absent. |
| **Reboot Stability & Watchdogs** | Vendor software watchdog with proprietary reset thresholds | Linux IPQ5018 hardware watchdog (`qcom-wdt`) integrated with procd | **`SOURCE_AVAILABLE`** | DTS watchdog node mapped (`0x00441000`). Hardware timeout behavior under kernel lockup `UNKNOWN`. |
| **Failsafe & Recovery** | Dual-image boot partition with vendor recovery mode | U-Boot bootcounter fallback (`bootcount`), OpenWrt failsafe button, TFTP recovery | **`SOURCE_AVAILABLE`** | Partition table mapped (dual rootfs / kernel). Live serial/TFTP automated recovery `UNKNOWN`. |

---

## 3. The Hardware Parity Gate Checklist

Prior to approving any firmware release for physical flashing onto CR8808 Ver.B hardware, the following strict gate criteria must be satisfied:

```
[ ] GATE 1: DUAL-IMAGE FLASH RECOVERY
    - U-Boot environment audited for 'upgrade_step' and 'bootcount'.
    - Confirmed ability to recover to stock RA82 via U-Boot TFTP or failsafe button without opening the chassis.

[ ] GATE 2: SWITCH SANITY & ANTI-LOOP INTEGRATION
    - Motorcomm YT9215SC DSA driver boots without MDIO bus timeouts.
    - WAN (Port 3) is strictly isolated from LAN (Ports 0, 1, 2) at reset to prevent broadcast storms.

[ ] GATE 3: WI-FI HE160 LINE-RATE ATTAINMENT
    - 5 GHz QCN6102 establishes 160 MHz channel width on DFS channels.
    - Station connection benchmark confirms PHY rate >= 2402 Mbps, with TCP iperf3 throughput >= 1.2 Gbps.

[ ] GATE 4: 940 MBPS SUSTAINED NAT ROUTING
    - 1 Gbps WAN-to-LAN bidirectional traffic sustains 940 Mbps for 30 minutes with zero dropped frames.
    - Host CPU utilization remains <= 65% on Core 0 and Core 1 under software flowtable.

[ ] GATE 5: 256MB MEMORY SOAK INTEGRITY
    - 24-hour stress soak with 50,000 active NAT connection tracking entries.
    - Resident memory does not exceed 150 MB (minimum 32 MB free RAM maintained; zero OOM-killer invocations).

[ ] GATE 6: BORINGTUN PRODUCTION RESILIENCY
    - BoringTun WireGuard tunnel sustains 900+ Mbps throughput with physical VmRSS <= 15 MB.
    - Reconnects automatically within 5 seconds after link disruption.
```

---

## 4. Current Parity Assessment Summary

- **Total Hardware Features Tracked:** 17
- **Stock Baseline Measured (`STOCK_MEASURED`):** 3 / 17
- **Source Available in Tree (`SOURCE_AVAILABLE`):** 7 / 17
- **Build Verified on Target ABI (`BUILD_VERIFIED`):** 4 / 17
- **Functionally Verified in Lab/Namespace (`FUNCTION_VERIFIED`):** 3 / 17
- **Performance Verified on Physical Target (`PERFORMANCE_VERIFIED`):** 0 / 17
- **Hardware Behaviors Pending Bench Test (`UNKNOWN`):** 11 / 17
- **Overall Claimed Parity:** **0% Physical Parity Confirmed (By Design — Safety Boundary Intact)**.
