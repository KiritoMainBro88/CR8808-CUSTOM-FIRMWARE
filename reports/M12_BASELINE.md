# Milestone M12: Live Router Architecture & Performance Baseline Report

- **Document ID:** `reports/M12_BASELINE.md`
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Firmware Baseline:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit `armv7l`)
- **Reporting Agent:** `@auditor` (Performance & Systems Auditor, Milestone M12 Swarm)
- **Receiving Authority:** Chief Architect / Swarm Coordinator (`@coordinator`)
- **Interrogation Method:** Class R0 100% In-Memory Read-Only SSH Stream (Zero Router Writes, Zero Uploads)
- **Audit Timestamp:** 2026-11-12 17:31:46 +07:00
- **Status:** **BASELINE AUDIT COMPLETE — EMPIRICAL MEASUREMENTS VERIFIED**

---

## 1. Executive Summary & Verification Boundaries

Pursuant to the **Milestone M12 Workstream A Charter**, the Performance & Systems Auditor has performed an exhaustive, non-destructive, read-only architectural interrogation of the live physical router over its LAN Dropbear SSH management interface (`192.168.31.1:56789`).

### 1.1 Strict Boundary Verification
- **Router State Mutation:** **ZERO WRITES.** Zero temporary files created on router filesystem (`/tmp` and `/data` untouched). Zero UCI modifications. Zero firewall alterations. Zero service restarts. Zero reboots.
- **Physical Flash / NVRAM:** **UNTOUCHED.** NAND flash partitions (`/dev/mtd*`) and UBI containers were accessed in strictly read-only mode.
- **Workstation Lab Directory:** [`D:\vibecode\test_wifi`](file:///D:/vibecode/test_wifi) **100% UNTOUCHED.**
- **Host Key Cryptographic Pinning:** Connection verified against pinned public key `SHA256:BwYCFt/UPVQ+Sj6/ZcbKf7yfTK5FqPFYB9uN7isGL64` via [`config/cr8818_host_key.pub`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/config/cr8818_host_key.pub).
- **Sanitized Telemetry:** Scrubbed via [`scripts/sanitize_telemetry.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/sanitize_telemetry.sh). Public report contains zero cleartext passwords, MACs, SSIDs, or private keys.

---

## 2. Silicon & System Architecture (Qualcomm IPQ5018)

### 2.1 SoC Identity & Topology
```text
Model         : Qualcomm Technologies, Inc. IPQ5018/AP-MP03.3
Board ID      : ap-mp03.3 (Xiaomi CR8808 Ver.B / CR8818)
CPU Cores     : 2x ARM Cortex-A53 (Operating in 32-bit AArch32 / armv7l mode)
CPU Implementer: 0x51 (Qualcomm), Part: 0x801, Variant: 0xa, Revision: 4
Clock Rate    : Fixed at 1.00 GHz (BogoMIPS: 48.00 per core)
CPU Features  : half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt 
                vfpd32 lpae evtstrm aes pmull sha1 sha2 crc32
```

> [!NOTE]
> The hardware features confirm full support for ARM NEON SIMD vectorization and hardware AES/SHA instructions (`aes pmull sha1 sha2`). This provides hardware acceleration capability for ChaCha20-Poly1305 and cryptographic operations in userspace BoringTun Rust.

### 2.2 CPU Frequency Scaling & Governors
- **Governor Interface:** `/sys/devices/system/cpu/cpu*/cpufreq` is **absent** from the vendor kernel build.
- **Clock Management:** Frequency is statically pinned in the Device Tree Clock Manager at 1000 MHz. Dynamic cpufreq governors (`ondemand`, `schedutil`, `performance`) are not active in this vendor kernel.

---

## 3. Memory Layout & RAM Accounting

### 3.1 Physical vs Linux Kernel Usable RAM
The hardware board is populated with a 256 MB DDR3L SDRAM chip. The physical address space is partitioned at boot:
- **Total Physical RAM:** 256.0 MB (262,144 kB)
- **Firmware / Hardware Reserved:** ~69.5 MB statically allocated at boot for Qualcomm NSS firmware, TrustZone (TZ), modem/QDSP sub-systems, and contiguous memory allocators (CMA).
- **Linux Usable `MemTotal`:** **186,920 kB (182.5 MB)**.

### 3.2 Live Kernel Memory Allocation Matrix
Measurements captured at timestamp 17:31:46:

| Memory Metric | Value (kB) | Value (MB) | % of Linux MemTotal | Operational Significance |
| :--- | :---: | :---: | :---: | :--- |
| **`MemTotal`** | 186,920 kB | 182.5 MB | 100.0% | Total kernel managed memory |
| **`MemFree`** | 21,868 kB | 21.4 MB | 11.7% | Completely unallocated pages |
| **`MemAvailable`** | **10,304 kB** | **10.1 MB** | **5.5%** | **CRITICAL: Truly evictable memory before OOM** |
| **`Slab`** | **60,300 kB** | **58.9 MB** | **32.3%** | Kernel slab cache allocations |
| $\llcorner$ **`SUnreclaim`** | **57,648 kB** | **56.3 MB** | **30.8%** | **95.6% of Slab CANNOT be reclaimed** |
| $\llcorner$ **`SReclaimable`** | 2,652 kB | 2.6 MB | 1.4% | Reclaimable dentries/inodes |
| **`Cached`** | 30,960 kB | 30.2 MB | 16.6% | Page cache files |
| **`Buffers`** | 4,192 kB | 4.1 MB | 2.2% | Block I/O buffer pages |
| **`Shmem`** | 17,272 kB | 16.9 MB | 9.2% | Shared memory and tmpfs mounts |
| **`Active(anon)`** | 43,900 kB | 42.9 MB | 23.5% | Active process anonymous heap/stack |
| **`SwapTotal`** | 0 kB | 0.0 MB | 0.0% | No swap device configured |

> [!CAUTION]
> **CRITICAL MEMORY PRESSURE:** `MemAvailable` is currently resting at only **10.1 MB (5.5% of total memory)**. Furthermore, **56.3 MB (95.6% of the kernel slab)** is classified as `SUnreclaim`. These allocations correspond to Qualcomm NSS DMA pools, `qca_ol` ring buffers, `umac` descriptors, and Netfilter tracking tables.

### 3.3 Top 10 Resident Memory Consumers (Userspace)

| PID | Command / Executable | VmRSS (Physical) | VmSize (Virtual) | Operational Profile & Footprint Notes |
| :---: | :--- | :---: | :---: | :--- |
| **1305** | `/data/wg_server` (WireGuard Go) | **20,768 kB (20.3 MB)** | **535,808 kB (523 MB)** | **Single largest memory consumer.** Peak VmHWM: 43.1 MB. |
| **1809** | `/usr/bin/messagingagent` | 1,800 kB (1.8 MB) | 6,836 kB (6.7 MB) | Xiaomi cloud MQTT/messaging service |
| **1720** | `nginx: worker process` | 996 kB (1.0 MB) | 6,208 kB (6.1 MB) | Web management interface backend |
| **3129** | `/usr/sbin/syslog-ng` | 872 kB (0.9 MB) | 4,464 kB (4.4 MB) | System logging daemon |
| **679** | `hostapd` | 656 kB (0.6 MB) | 4,248 kB (4.1 MB) | IEEE 802.11 AP authenticator |
| **1534** | `nginx: master process` | 672 kB (0.7 MB) | 5,964 kB (5.8 MB) | Nginx master process supervisor |
| **3265** | `/usr/sbin/trafficd` | 548 kB (0.5 MB) | 1,696 kB (1.7 MB) | Local traffic accounting and stats |
| **3092** | `flight_recorder.sh` | 512 kB (0.5 MB) | 1,288 kB (1.3 MB) | Persistent logging script |
| **1** | `/sbin/procd` | 516 kB (0.5 MB) | 1,404 kB (1.4 MB) | OpenWrt process manager / init |
| **2009** | `/usr/sbin/dnsmasq` | 2,044 kB (2.0 MB) | 2,504 kB (2.4 MB) | Local DNS cache and DHCP server |

---

## 4. Ethernet Switch: Motorcomm YT9215SC @ MDIO 0x1d

### 4.1 Switch Architecture & Interface Topology
The device utilizes an external **Motorcomm YT9215SC** Gigabit Ethernet switch connected via MDIO at bus address `0x1d`.
- **Driver Architecture:** Controlled via proprietary Qualcomm SSDK driver (`qca_ssdk`, 665,456 bytes) and `yt_switch` kernel module (343,529 bytes). Exposed to userspace through OpenWrt `swconfig dev switch0`.
- **Physical Link Status:**

| Port | Logical Interface | Link Status | Speed / Duplex | Rx Good Bytes | Tx Good Bytes | Pause Frames |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Port 0** | CPU Internal Port | Down (Internal) | - | 0 | 0 | 0 |
| **Port 1** | WAN (`eth0`) | **UP** | 1000baseT Full-Duplex | 3,823,566 B | 148,770 B | 0 |
| **Port 2** | LAN Port 1 (`eth1`) | **UP** | 1000baseT Full-Duplex | 770 B | 4,656 B | 3,270 (Rx) |
| **Port 3** | LAN Port 2 | DOWN | Unconnected | 0 | 0 | 0 |
| **Port 4** | LAN Port 3 | DOWN | Unconnected | 0 | 0 | 0 |
| **Port 5** | Expansion / Unused | DOWN | Unconnected | 0 | 0 | 0 |
| **Port 6** | CPU GMAC Trunk | DOWN (Internal) | - | 0 | 0 | 0 |

### 4.2 Switch Capabilities & Flow Control
- **VLAN Support:** `enable_vlan: 1`, Max frame size: 1,526 bytes.
- **Hardware Flow Control:** Active on Port 1 and Port 2 (`txflow rxflow`). Port 2 recorded 3,270 received pause frames, confirming hardware backpressure signaling during bursts.

---

## 5. Qualcomm NSS Fast-Path & Hardware Acceleration

### 5.1 NSS Kernel Driver Topology
The Qualcomm Network Subsystem (NSS) consists of dedicated hardware acceleration engines running proprietary firmware:
- `qca_nss_drv` (826,603 bytes): Core NSS host driver communication layer.
- `qca_nss_dp` (36,064 bytes): NSS Data Plane interface.
- `ecm` (Enhanced Connection Manager, 656,294 bytes): Dynamic hardware acceleration front-end. Intercepts Netfilter `nf_conntrack` sessions and offloads active TCP/UDP tuples directly into NSS hardware tables.
- `qca_nss_pppoe`, `qca_nss_pptp`, `qca_nss_l2tpv2`, `qca_nss_gre`: Hardware acceleration modules for tunneling protocols.

### 5.2 Conntrack & Flow Acceleration State
- **Active Connections:** 463 active conntrack sessions.
- **Maximum Table Limit:** 16,384 sessions (`nf_conntrack_max`).
- **NSS Hardware Offload Coverage:**
  - Standard IPv4 NAT and routed unicast flows: **Accelerated via NSS hardware.**
  - PPPoE encapsulation: **Accelerated via NSS hardware.**
  - Wi-Fi 6 bridged datapath (`wifi_3_0` + `umac`): **Accelerated via NSS offload.**
  - WireGuard UDP (`10.99.0.1:51820`): **UNACCELERATED (Host Path / CPU0 SoftIRQ).**
  - Unmapped IPv6 packets: **UNACCELERATED (Host Path / CPU0 SoftIRQ).**

---

## 6. Wi-Fi Architecture & QCN6102 5G HE160 Capabilities

### 6.1 Wireless Subsystem Overview
The router features a dual-radio concurrent Wi-Fi 6 (802.11ax) design:

```
+-------------------------------------------------------------------------------+
|                       CR8808 Ver.B WIRELESS SUBSYSTEM                         |
+------------------------------------+------------------------------------------+
| 5 GHz Radio (QCN6102 via PCIe)     | 2.4 GHz Radio (Internal IPQ5018 SoC)     |
+------------------------------------+------------------------------------------+
| Interface: wl0 / phy1 (PCIe bus)   | Interface: wl1, wl13 / phy0 (SoC AHB)    |
| Standard : 802.11a/n/ac/ax (HE160) | Standard : 802.11b/g/n/ax (HE20/HE40)    |
| Channel  : 40 (5200 MHz, 160 MHz)  | Channel  : 1 (2412 MHz, 20 MHz)          |
| Bit Rate : 2,401.9 Mb/s (2.4 Gbps) | Bit Rate : 286.8 Mb/s                    |
| TxPower  : 24.0 dBm                | TxPower  : 23.0 dBm                      |
| Antennas : 2x2 MIMO                | Antennas : 2x2 MIMO                      |
+------------------------------------+------------------------------------------+
```

### 6.2 5 GHz QCN6102 Empirical Capabilities
- **Bandwidth Support:** 20 MHz, 40 MHz, 80 MHz, 160 MHz, and 80+80 MHz.
- **Modulation & Coding:** Up to 1024-QAM (MCS 0-11, 2 spatial streams = 2,402 Mbps peak).
- **A-MPDU Aggregation:** Maximum RX A-MPDU length: **65,535 bytes** (exponent: `0x003`), No time spacing restriction.
- **A-MSDU Aggregation:** Maximum A-MSDU length: **7,935 bytes**; Max MPDU length: **11,454 bytes**.
- **Hardware Acceleration:** NSS offload integration active (`qca_ol` + `umac` + `wifi_3_0`).
- **Retries Limits:** Short retry limit: 7; Long retry limit: 4.

---

## 7. SoftIRQ & Interrupt Imbalance Across CPU Cores

### 7.1 Empirical Delta Measurement (3-Second Sampling Window)
Data captured via [`performance/benchmarks/softirq_profiler.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/performance/benchmarks/softirq_profiler.sh):

```
SoftIRQ Type | CPU0 Delta   | CPU1 Delta   | Total Delta  | Rate/sec     | Imbalance %    
-----------------------------------------------------------------------------------------
NET_RX       | 4263         | 61           | 4324         | 1441.3       | 97.2%          
NET_TX       | 1            | 0            | 1            | 0.3          | 100.0%         
TASKLET      | 2180         | 0            | 2180         | 726.7        | 100.0%         
TIMER        | 348          | 348          | 696          | 232.0        | 0.0%           
SCHED        | 295          | 327          | 622          | 207.3        | 5.1%           
RCU          | 358          | 306          | 664          | 221.3        | 7.8%           
-----------------------------------------------------------------------------------------
```

### 7.2 Cumulative SoftIRQ Distribution
- **`NET_RX` (Cumulative):**
  - CPU0: **316,529,461 softirqs (99.60%)**
  - CPU1: **1,263,428 softirqs (0.40%)**
- **`TASKLET` (Cumulative):**
  - CPU0: **99,542,628 (100.00%)**
  - CPU1: **0 (0.00%)**
- **`NET_TX` (Cumulative):**
  - CPU0: **52,308 (99.99%)**
  - CPU1: **2 (0.01%)**

### 7.3 Receive Packet Steering (RPS) & RFS Configuration
- Every single `/sys/class/net/*/queues/rx-*/rps_cpus` file is currently set to **`0` (DISABLED)** across `eth0`, `eth1`, `br-lan`, `wl0`, `wl1`, and `wg0`.
- `rps_flow_cnt`: Set to **`0`** across all interfaces.
- `rps_sock_flow_entries`: Set to **`0`**.

> [!IMPORTANT]
> **ROOT CAUSE OF IMBALANCE:** Because RPS is disabled across all network interfaces, the kernel processes packet softirqs exclusively on the CPU that handles the hardware interrupt. Because ARM GIC interrupt affinities for `nss_queue0`, `pci0_wlan_ce_*`, and GMAC default to CPU0, **CPU0 bears 99.6% of all network softirqs**, while CPU1 remains completely idle with respect to network processing.

---

## 8. Network & TCP Stack Configuration

### 8.1 Network Backlog & Buffer Configuration
- `net.core.netdev_max_backlog = 10000` (Sufficient ring backlog)
- `net.core.netdev_budget = 300`
- `net.core.dev_weight = 64`
- `net.core.somaxconn = 128` (**Severely restricted** listen backlog)
- `net.ipv4.tcp_max_syn_backlog = 128` (**Severely restricted** SYN backlog)

### 8.2 TCP Window Buffers
- `net.core.rmem_default = 524288` (512 kB)
- `net.core.rmem_max = 4194304` (4 MB)
- `net.core.wmem_default = 524288` (512 kB)
- `net.core.wmem_max = 4194304` (4 MB)
- `net.ipv4.tcp_rmem = 4096 524288 4194304`
- `net.ipv4.tcp_wmem = 4096 524288 4194304`
- `net.ipv4.tcp_congestion_control = cubic` (available: `cubic`, `reno`)

### 8.3 Queue Disciplines (`tc qdisc`)
- `eth0`: `qdisc fq_codel limit 1024p flows 1024 quantum 1514 target 5.0ms interval 100.0ms ecn`
- `eth1`: `qdisc fq_codel limit 1024p flows 1024 quantum 1514 target 5.0ms interval 100.0ms ecn`
- `wg0`: `qdisc fq_codel limit 1024p flows 1024 quantum 1420 target 5.0ms interval 100.0ms ecn`
- `br-lan`: `qdisc noqueue`
- `wl0` / `wl1`: `qdisc noqueue`

---

## 9. Baseline Sign-Off

This document establishes the official empirical baseline for Milestone M12. All measurements are backed by sanitized raw artifacts and repeatable via the automated benchmarking suite in `performance/benchmarks/`.
