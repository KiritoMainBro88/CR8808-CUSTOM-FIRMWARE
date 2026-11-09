# Feature Parity Matrix: Xiaomi RA82 Stock vs. Custom DSA OpenWrt

- **Document ID:** `docs/FEATURE_PARITY_MATRIX.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 + Motorcomm YT9215S/SC)
- **Baseline Firmware:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, ARMv7 32-bit musl)
- **Target Platform:** OpenWrt / ImmortalWrt Clean DSA Baseline (Linux 6.18, `qualcommax/ipq50xx`, AArch64 64-bit musl)
- **Status:** Authoritative Pre-P2 Reference Specification
- **Revision:** Round 3 Review (Generic Package Decoupling, Hardware Demarcation, Sole Rust WG Engine)

---

## 1. Empirical Status Taxonomy

To eliminate ambiguity and unverified marketing claims, every feature in this matrix is classified strictly under empirical evidence levels:

| Status Code | Level | Definition |
|---|---|---|
| **`SOURCE_VERIFIED`** | L1 | Board-specific DTS nodes, target hardware drivers, and kernel configurations exist and have been inspected in the CR881x source tree. |
| **`GENERIC_PACKAGE_AVAILABLE`** | L1-G | Userland package or service exists in standard OpenWrt feeds, but target-specific hardware integration has not yet been verified. |
| **`BUILD_VERIFIED`** | L2 | Successfully compiled into a target binary (userspace tool, kernel package, or full sysupgrade image) for the target ABI without errors. |
| **`NOT_BUILD_VERIFIED`** | L2-P | Source code and target ABI identified, but compilation for target platform has not yet been performed. |
| **`BOOT_VERIFIED`** | L3 | Booted successfully into the OS on physical target hardware without kernel panic or watchdog loop. |
| **`FUNCTION_VERIFIED`** | L4 | Feature operations executed and validated against unit/integration tests on target device under live conditions. |
| **`PERFORMANCE_VERIFIED`**| L5 | Throughput, packet-loss, latency, and resource metrics measured and verified against predefined acceptance thresholds. |
| **`SOAK_TESTED`** | L6 | Executed under continuous stress load (>24 hours) with zero memory leaks, thread lockups, or kernel panics. |
| **`REPORTED_UNVERIFIED`** | U0-R | Documented in community reports or vendor teardowns, awaiting live device verification. |
| **`UNKNOWN`** | U0 | Hardware behavior, register definition, or software compatibility cannot be determined from existing data; requires empirical device testing. |
| **`NOT_SELECTED`** | N0-S | Feature is deliberately excluded in architectural favor of a chosen alternative (e.g. In-Kernel WireGuard excluded in favor of BoringTun Rust). |
| **`NOT_IMPLEMENTED`** | N0 | Feature is intentionally excluded (e.g. proprietary vendor cloud tethering) or out of scope for the current phase. |

---

## 2. Feature Parity Matrix

| Feature Category | Specific Feature | Stock Implementation (Xiaomi RA82 v1.4.31) | Target OpenWrt Implementation (Linux 6.18 DSA) | Upstream Source Reference | Dependencies | Verification Procedure | Acceptance Criteria | Current Evidence Status |
|---|---|---|---|---|---|---|---|---|
| **Ethernet & Switching** | 1x WAN + 3x LAN GbE Ports | Proprietary `yt_switch.ko` vendor driver + `eth0`/`eth1` bridging | Linux DSA driver exposing `lan1` (P0), `lan2` (P1), `lan3` (P2), `wan` (P3) via SGMII Port 8 + internal GE PHY Port 4 | `ipq5018-cr881x.dts` & `tag_yt921x_enhanced.c` | MDIO bus 1 (GPIO 36/37), GPIO 39 reset, GMAC0/1 | `ip link show`, bidirectional `iperf3` across each physical port | All 4 ports independently addressable; full duplex 1000BASE-T link negotiation | **`SOURCE_VERIFIED`** |
| **Ethernet & Switching** | Hardware VLAN Tagging & Isolation | Proprietary SSDK ioctl commands via userland daemon | Standard Linux 802.1Q switchdev offload (`bridge vlan`) | Upstream DSA core (`net/dsa/`) | `kmod-bridge`, DSA tag driver | Configure trunk port with tagged VLANs 10/20; capture packets with tcpdump | Packets egress with correct 802.1Q tags; isolation between unbridged VLANs | **`GENERIC_PACKAGE_AVAILABLE`** (Pending driver switchdev test) |
| **Ethernet & Switching** | Link Status & PHY Renegotiation | Polling thread in `yt_switch` kernel module | Upstream Linux Phylink framework with interrupt or periodic polling | `drivers/net/phy/phylink.c` | MDIO bus driver, Motorcomm PHY driver | Unplug and replug cable across all 4 ports at 10M/100M/1000M speeds | Link UP/DOWN events delivered to kernel log within 500 ms; carrier flags updated | **`SOURCE_VERIFIED`** |
| **Ethernet & Switching** | Switch Reset & Power Sequencing | Vendor GPIO 39 toggle in `yt_switch.ko` | GPIO 39 reset handling (Investigating reset timings vs. `gpio-hog` workaround) | `zcop/immortalwrt/issues/5` & TLMM DTS | GPIO 39, TLMM pin controller | 20-cycle automated reboot test (cold boot & warm reboot) | Zero MDIO chip ID `0xffff` errors; 100% Ethernet probe success across 20 cycles | **`UNKNOWN`** (Pending hardware reboot verification) |
| **Ethernet & Switching** | Jumbo Frames / MTU Configuration | Fixed 1500 byte MTU; buffer allocations hardcoded | Configurable interface MTU up to 9000 bytes via DSA master | `dwmac-ipq5018.c` MTU ops | NIC driver buffer ring support | Set MTU 9000 on `lan1`; send oversized ICMP packets: `ping -s 8972 -M do <target>` | Successful transmit and receive without frame drops or fragmentation | **`UNKNOWN`** (Pending switch buffer limit test) |
| **Wi-Fi Subsystem** | 5 GHz 802.11ax (HE160 Mandatory) | Vendor QSDK driver (`qca-wifi`), 2402 Mbps theoretical | Upstream `ath11k` driver (QCN6102 / QCN6122 radio, 160 MHz width mandatory) | `ipq5018-cr881x.dts` & `drivers/net/wireless/ath/ath11k/` | `ath11k-firmware-qcn6102`, DRAM BDF at `0x4d100000` (from `0:ART`) | Associate Intel AX210 / BE200 client at 160 MHz width; run `iperf3 -P 8` | PHY rate reports 2402 Mbps; sustained TCP throughput > 900 Mbps; HE160 preserved | **`SOURCE_VERIFIED`** |
| **Wi-Fi Subsystem** | 2.4 GHz 802.11ax | Vendor QSDK driver (`qca-wifi`), 574 Mbps theoretical | Upstream `ath11k_ahb` driver (IPQ5018 integrated radio) | `ipq5018-cr881x.dts` & `ath11k/ahb.c` | `ath11k-firmware-ipq5018`, DRAM BDF at `0x4c400000` (from `0:ART`) | Associate 2.4 GHz Wi-Fi 6 client at 40 MHz channel width; run bidirectional iperf3 | PHY rate reports 574 Mbps; stable beacon generation without carrier drops | **`SOURCE_VERIFIED`** |
| **Wi-Fi Subsystem** | WPA3-Personal (SAE) | Vendor hostapd with proprietary SAE patch | Modern open-source `hostapd` with `wpad-basic-mbedtls` or `wpad-wolfssl` | OpenWrt `package/network/services/hostapd` | `libmbedtls` / `libwolfssl` | Authenticate WPA3-only and WPA2/WPA3 mixed clients; verify PMKID exchange | Seamless 4-way handshake and SAE simultaneous authentication without auth loops | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Wi-Fi Subsystem** | Fast Roaming (802.11k/v/r) | Xiaomi proprietary `xqwhc` / mesh steering daemon | Standards-compliant OpenWrt `usteer` or `dawn` daemon | `package/network/services/usteer` | `hostapd-utils`, `ubus` | Roam between AP nodes; observe BSS Transition Management frames in Wireshark | Client handoff completes under 100 ms without TCP connection reset | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Wi-Fi Subsystem** | Multi-SSID / Guest Isolation | Xiaomi guest network with proprietary ebtables rules | Standard OpenWrt Virtual AP (VAP) mapped to isolated firewall zones | OpenWrt `netifd` + `wireless` UCI | `firewall4`, `nftables` | Connect to Guest SSID; attempt ping to main LAN gateway and host devices | DHCP lease granted from guest subnet; 100% dropped packets to main LAN | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Wi-Fi Subsystem** | Dynamic Frequency Selection (DFS) | Vendor radar detection algorithm in closed firmware | Linux kernel `ath11k` regulatory domain & CAC state machine | `net/wireless/reg.c` & `ath11k/wmi.c` | CRDA / wireless regulatory database | Configure 5 GHz channel 52-64 / 100-140; observe 60-second CAC period | AP halts transmission during CAC; radar detect triggers channel switch | **`SOURCE_VERIFIED`** |
| **Routing & Core IP** | IPv4 Forwarding & NAT | Linux 4.4 iptables + QSDK NSS / ECM acceleration | Linux `nftables` + `flow_offload` (software flowtable) | Upstream Linux `net/netfilter/nf_flow_table.c` | `kmod-nft-offload`, `firewall4` | Bidirectional `iperf3` between WAN and LAN over 1 Gbps physical link | Sustained 940+ Mbps NAT throughput with CPU utilization < 60% per core | **`SOURCE_VERIFIED`** |
| **Routing & Core IP** | IPv6 Prefix Delegation & SLAAC | Vendor customized `odhcpd` with cloud DNS enforcement | Modern upstream `odhcpd-ipv6only` with standard SLAAC/DHCPv6-PD | OpenWrt `package/network/services/odhcpd` | Native kernel IPv6 stack | WAN connects to upstream IPv6 DHCP-PD server; LAN clients autoconfigure | Global IPv6 unicast assigned to LAN; 2a00::/128 ping reachability verified | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Routing & Core IP** | DNS Resolution & Local Caching | Vendor `dnsmasq` 2.80 with Xiaomi cloud redirect | Modern upstream `dnsmasq` 2.90+ with DNSSEC and ECS support | `package/network/services/dnsmasq` | `libnettle` (for DNSSEC) | Query public and local domains via `dig`; verify DNSSEC signature validation | Resolution time < 5 ms for cached records; invalid DNSSEC RRSIGs rejected | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Routing & Core IP** | UPnP & NAT-PMP Dynamic Ports | Vendor `miniupnpd` with cloud port hooks | Upstream `miniupnpd` with nftables backend integration | `package/network/services/miniupnpd` | `nftables` dynamic set support | Run UPnP client test tool (e.g. `upnpc -a`); verify port opening in nftables | Dynamic port mapping created in nftables set; closed upon lease expiration | **`GENERIC_PACKAGE_AVAILABLE`** |
| **VPN Subsystem** | WireGuard Userspace Daemon | `wireguard-go` (Go userspace runtime, high virtual memory) | **`boringtun-cli`** (Rust userspace runtime, **sole WireGuard engine**) | Cloudflare BoringTun 0.7.1 upstream + local signalfd patch | Rust toolchain, `aarch64-unknown-linux-musl` | Start BoringTun tunnel; execute 24-hour sustained bidirectional traffic test | Handshake < 15 ms; peak VmRSS < 15 MB; zero thread aborts or OOM events | **`NOT_BUILD_VERIFIED`** (ARMv7 tested; AArch64 target in P4) |
| **VPN Subsystem** | In-Kernel WireGuard Module | Not available in stock Xiaomi Linux 4.4 kernel | Excluded from final firmware in favor of BoringTun Rust | Upstream Linux `drivers/net/wireguard/` | N/A | N/A | Architectural mandate: BoringTun Rust is the sole engine | **`NOT_SELECTED`** |
| **Traffic Control / QoS** | Bufferbloat Mitigation | Xiaomi proprietary QoS (static priority queuing) | CAKE / FQ-CoDel via `sqm-scripts` | `package/network/utils/sqm-scripts` | `kmod-sched-cake`, `tc` | Run Waveform Bufferbloat test during saturated 1 Gbps download/upload | Bufferbloat grade A or A+; latency under load increases by less than 5 ms | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Hardware Offload** | Qualcomm NSS Acceleration | Active in stock firmware via proprietary QCA-SSDK blobs | Separated to Phase 2 (clean baseline verified first) | `qcom,nss-dp` + NSS firmware 12.5-210 | Out-of-tree NSS kernel modules | N/A in Phase 1 (Baseline relies entirely on software flowtable) | Deferred to Phase 2 after baseline stability is certified | **`NOT_IMPLEMENTED`** (Phase 1 Baseline) |
| **Management & Web UI** | Web Administrative Console | Xiaomi proprietary LuCI skin + closed Javascript | Standard OpenWrt LuCI (modern Bootstrap / Argon responsive theme) | OpenWrt `feeds/luci/modules/luci-base` | `uhttpd` or `nginx-light`, `rpcd` | Navigate web UI on mobile and desktop browsers; configure network settings | Page load < 300 ms; clean configuration commit without vendor telemetry calls | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Management & Access** | SSH Administrative Access | Vendor-locked root shell (requires exploit or development unlock) | Native Dropbear / OpenSSH with Ed25519 public key authentication | `package/network/services/dropbear` | Linux PTY subsystem | Connect from administrative workstation via SSH key; verify command execution | Immediate authenticated shell access; password authentication disabled | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Management & Telemetry** | System Monitoring & Statistics | Xiaomi proprietary cloud metrics reporting | Local-only `luci-app-statistics` / Collectd / Prometheus node-exporter | `feeds/luci/applications/luci-app-statistics` | `collectd-mod-cpu`, `collectd-mod-memory` | Observe real-time per-core CPU, RAM breakdown, and per-interface traffic | Comprehensive real-time metrics without outbound cloud data transmission | **`GENERIC_PACKAGE_AVAILABLE`** |
| **Vendor Cloud Services** | Mi Home App / Cloud Remote Access | Xiaomi cloud binding daemon (`xqapp`, `xqanalytics`) | Not implemented (Replaced by WireGuard remote access + LuCI) | N/A (Intentionally eliminated for privacy and security) | None | N/A | Total elimination of closed telemetry daemons and unsolicited cloud pings | **`NOT_IMPLEMENTED`** (Intentional Drop) |
| **Storage & Firmware** | Dual-Slot A/B NAND Layout | Dual UBI partitions (`rootfs` / `rootfs_1`) with U-Boot switching | Dual-slot UBI preservation with inactive slot flashing | `drivers/mtd/nand/raw/` & UBI subsystem | Winbond W25N01GWZEIG NAND driver | Verify MTD layout matches stock geometry; stage image in inactive slot | Inactive slot flashed without modifying active slot or bootloader partition | **`SOURCE_VERIFIED`** |
| **Storage & Firmware** | RF Calibration Integrity | `0:ART` partition containing device-specific factory Wi-Fi calibration | Partition `0:ART` (NAND offset `0x780000`, 1 MiB) mapped read-only in DTS | Linux MTD fixed partitions | MTD subsystem | Dump and SHA-256 hash `0:ART` partition; verify match against factory dump | Hash identical; ath11k driver initializes RF stages without calibration errors | **`SOURCE_VERIFIED`** |
| **Recovery & Failsafe** | U-Boot TFTP Recovery | Xiaomi U-Boot holding reset writes image directly to NAND | Maintained as emergency factory unbrick; does NOT provide RAM-only netboot | Xiaomi stock bootloader (`0:bootloader`) | TFTP server, Ethernet LAN link | Capture TFTP packets during boot with reset held | U-Boot issues TFTP read request; recovery image writes to NAND | **`REPORTED_UNVERIFIED`** (Known Xiaomi behavior; pending packet capture) |

---

## 3. Summary of Status Breakdown

- **Total Assessed Capabilities:** 26
- **`SOURCE_VERIFIED`:** 7 (26.9%) — Hardware DTS, switch driver, radio driver, MTD geometry, PHY renegotiation.
- **`GENERIC_PACKAGE_AVAILABLE`:** 11 (42.3%) — Hostapd, usteer, odhcpd, dnsmasq, miniupnpd, sqm, LuCI, Dropbear, statistics, VLAN offload.
- **`NOT_BUILD_VERIFIED`:** 1 (3.8%) — BoringTun Rust AArch64 binary.
- **`NOT_SELECTED`:** 1 (3.8%) — In-Kernel WireGuard (excluded in favor of BoringTun Rust).
- **`UNKNOWN`:** 2 (7.7%) — MTU buffer limit; GPIO39 switch initialization & reboot survival.
- **`REPORTED_UNVERIFIED`:** 1 (3.8%) — Stock U-Boot TFTP flash recovery behavior.
- **`NOT_IMPLEMENTED`:** 3 (11.5%) — Phase 1 NSS acceleration (deferred to Phase 2); Mi Home cloud telemetry (intentional drop).
- **`BOOT_VERIFIED` / `FUNCTION_VERIFIED` / `PERFORMANCE_VERIFIED` / `SOAK_TESTED`:** 0 (0.0%) — Strictly pending physical hardware Phase P5 execution.
