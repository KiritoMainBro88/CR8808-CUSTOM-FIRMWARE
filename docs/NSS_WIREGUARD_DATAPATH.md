# WireGuard Datapath & Qualcomm NSS Offload Interaction: BoringTun Rust on CR8818

- **Document ID:** `docs/NSS_WIREGUARD_DATAPATH.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 + NSS NPU @ 1.0 GHz)
- **Target Platform:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Scope:** Detailed Cryptographic Division of Labor, Two-Tier Datapath Analysis, ECM Offload Scope, and Benchmark Protocol
- **Status:** Architectural Specification & Datapath Analysis

---

## 1. Executive Summary & Core Cryptographic Reality

The integration of **BoringTun Rust** as the exclusive WireGuard engine on the Xiaomi CR8808 Ver.B router addresses a critical CPU and memory limitation:
- The stock Go WireGuard daemon (`wireguard-go`) relies on a garbage-collected runtime that pre-allocates large virtual memory arenas (e.g. `VmSize` 522 MB) and incurs periodic garbage collection cycles.
- BoringTun Rust operates with a deterministic, lightweight footprint (peak `VmRSS < 15 MB`, zero garbage collection pauses).

However, an essential technical distinction must be maintained regarding Qualcomm NSS hardware offload:
> [!IMPORTANT]
> **Silicon Cryptographic Limitation:**
> The Qualcomm IPQ5018 SoC contains hardware crypto acceleration engines for **IPsec** (AES-CBC, AES-GCM, SHA1/256) and **DTLS**.
> **The IPQ5018 does NOT possess hardware acceleration for ChaCha20-Poly1305** (the sole cipher suite utilized by the WireGuard protocol).
> Therefore, NSS **CANNOT** decrypt or encrypt WireGuard packets directly in hardware. Any claim that NSS provides full end-to-end WireGuard cryptographic offload is technically unfounded.

This document formalizes the **Two-Tier Hybrid Acceleration Datapath**, delineating exactly which packet stages are offloaded to NSS and which stages are processed by the host Cortex-A53 CPU using ARM NEON vector instructions.

---

## 2. The Two-Tier Hybrid Acceleration Datapath

```
                                  +------------------------------------+
                                  |         Internet / Remote Peer     |
                                  +-----------------+------------------+
                                                    |
                                    Encrypted UDP Traffic (Port 51821)
                                                    |
                                                    v
                                          [ Physical WAN Port ]
                                                    |
                                                    v
+==================================================================================================+
| QUALCOMM NSS HARDWARE NPU LAYER (retail_router0.bin)                                             |
|                                                                                                  |
|   1. Ingress Processing:                                                                         |
|      - Frame parsing, checksum offload, L2/L3 validation.                                        |
|   2. Outer Tunnel Acceleration (ECM Offload):                                                    |
|      - Qualcomm ECM detects high-volume UDP stream on port 51821.                                |
|      - Fast-paths outer UDP delivery to host socket without software netfilter traversal.        |
+===================================================+==============================================+
                                                    |
                                    Outer UDP Datagram (Encrypted)
                                                    |
                                                    v
+==================================================================================================+
| LINUX KERNEL NETWORKING STACK (Linux 6.18)                                                       |
|                                                                                                  |
|   UDP Socket Buffer (SO_RCVBUF) ---> Passed to Userspace /dev/net/tun                            |
+===================================================+==============================================+
                                                    |
                                                    v
+==================================================================================================+
| USERSPACE BORINGTUN RUST DAEMON (AArch64 musl / ARMv7 NEON)                                     |
|                                                                                                  |
|   1. WireGuard State Machine & Session Key Handshake.                                            |
|   2. Cryptographic Execution on Cortex-A53 CPU:                                                  |
|      - ChaCha20 Stream Cipher Decryption (ARMv8 / ARMv7 NEON Vectorized).                        |
|      - Poly1305 One-Time MAC Authentication (NEON SIMD Multiply-Accumulate).                     |
|   3. Plaintext Extraction: Emits clean IP packet into /dev/net/tun.                              |
+===================================================+==============================================+
                                                    |
                                      Plaintext IP Packet (e.g. 10.8.0.2)
                                                    |
                                                    v
+==================================================================================================+
| LINUX KERNEL ROUTING & FIREWALL (tun0 / wg1 Interface)                                           |
|                                                                                                  |
|   1. Linux IP Routing: Destination lookup (LAN subnet vs local host).                            |
|   2. Netfilter / nftables: Zone firewall rules (VPN to LAN policy).                              |
|   3. In-Kernel Software Flowtable (Clean Baseline) OR NSS L3 Acceleration:                       |
|      - Forwarded to destination Ethernet port.                                                   |
+===================================================+==============================================+
                                                    |
                                                    v
                                          [ Destination LAN Host ]
```

---

## 3. Detailed Division of Labor: NSS vs. Host CPU

| Datapath Stage | Responsible Processing Entity | Acceleration Mechanism & Characteristics |
|---|---|---|
| **Outer WireGuard UDP Transport** | **Qualcomm NSS NPU** (via ECM) | **Hardware Offloaded:** Outer UDP (Port 51821) encapsulation, IP routing, NAT, checksum verification, and GMAC DMA. |
| **ChaCha20 Decryption / Encryption** | **Host CPU (Cortex-A53)** | **SIMD Accelerated:** Vectorized using ARM NEON instructions (zero hardware NPU offload). |
| **Poly1305 MAC Verification / Tagging**| **Host CPU (Cortex-A53)** | **SIMD Accelerated:** Vectorized polynomial arithmetic in BoringTun Rust. |
| **Inner Tunnel IP Routing & Firewall** | **Linux Kernel / NSS** | **Hybrid:** Netfilter evaluates policy; subsequent established plaintext flows can be accelerated if interfaces are supported by ECM. |
| **LAN Physical Delivery** | **Motorcomm YT9215SC Switch** | **Hardware Switched:** Transmitted across physical LAN port at 1 Gbps wire speed. |

### 3.1 Net Engineering Benefit of the Hybrid Model:
Even though WireGuard cryptography cannot be offloaded to the NSS NPU:
1. **CPU Offload for Network Overhead:** In traditional software routing, the host CPU spends significant cycles processing physical interface interrupts, SKB allocations, checksum validation, and NAT table lookups.
2. **Dedicated Crypto Capacity:** By delegating the outer UDP transport, GMAC DMA, and physical PHY handling to the NSS NPU, the dual-core Cortex-A53 host CPU is freed up to dedicate near **100% of its execution cycles to BoringTun's NEON cryptographic routines**.
3. **Absence of Garbage Collection:** Unlike Go WireGuard, BoringTun Rust does not invoke GC assist pauses, eliminating latency jitter during VoIP calls or gaming sessions over VPN.

---

## 4. Controlled Testing & Benchmark Architecture

To safely evaluate BoringTun Rust on physical hardware without endangering the active production connection:

### 4.1 Strict Parallel Isolation Architecture:

```
+--------------------------------------------------------------------------------------------------+
| PRODUCTION TUNNEL (ACTIVE)                 | EXPERIMENTAL TUNNEL (TESTING)                       |
+--------------------------------------------+-----------------------------------------------------+
| Daemon:      wireguard-go (Active)         | Daemon:      boringtun-cli (Isolated Test)          |
| Port:        UDP 51820                     | Port:        UDP 51821                              |
| Interface:   wg0                           | Interface:   wg1                                    |
| Subnet:      Existing Production Subnet    | Subnet:      Dedicated Isolated Subnet (e.g. 10.99) |
| Routing:     Main Workstation Production   | Routing:     Explicit Host Route ONLY (No Default)  |
| Persistence: Stock Procd Boot Enabled      | Persistence: RAM (/tmp) Staged ONLY (No Boot Auto)  |
+--------------------------------------------------------------------------------------------------+
```

### 4.2 Mandatory Safety & Verification Rules for wg1 Test:
1. **Zero Default Route Hijacking:** The `wg1` test tunnel must **never** set `AllowedIPs = 0.0.0.0/0` or alter the kernel default gateway. It must only route a single dedicated test peer IP.
2. **Independent Port Forwarding:** If the router is deployed as a secondary AP or behind an upstream gateway, UDP port `51821` must be explicitly verified or port-forwarded from the upstream edge router before expecting inbound handshakes.
3. **No Flash / No Persistent Config:** All binaries and test configurations must reside strictly in RAM (`/tmp/boringtun`). A hardware reboot must return the router 100% to its prior state.

### 4.3 Objective Benchmark Metric Protocol:
To eliminate ungrounded throughput assertions (such as speculative claims of 250–350 Mbps), performance must be empirically measured and logged across eight concrete parameters:

| Benchmark Parameter | Measurement Tool / Source | Unit of Measurement | Acceptance Threshold |
|---|---|---|---|
| **Sustained TCP Throughput** | `iperf3 -c <peer> -t 60` | Mbits/sec | `ACCEPTANCE_TARGET` (Baseline record) |
| **Sustained UDP Throughput** | `iperf3 -u -b 500M -c <peer>` | Mbits/sec & Jitter (ms) | `ACCEPTANCE_TARGET` |
| **Per-Core CPU Utilization** | `mpstat -P ALL 1 60` / `top` | %usr, %sys, %sirq, %idle | Must observe CPU1 vs CPU0 load balance |
| **Resident Memory (RSS)** | `grep -i vmrss /proc/<pid>/status`| Kilobytes (KB) | **< 15,000 KB (15 MB)** |
| **Peak Memory (HWM)** | `grep -i vmhwm /proc/<pid>/status`| Kilobytes (KB) | Record maximum resident watermark |
| **Latency Under Load (P50/P95/P99)**| `ping -i 0.2 -c 500 <peer>` | Milliseconds (ms) | Compare P99 latency against Go baseline |
| **SoftIRQ Overhead** | `/proc/softirqs` (NET_RX / NET_TX) | Rate (interrupts/sec) | Confirm NAPI behavior under load |
| **Long-Term Soak Stability** | 4-hour continuous 50 Mbps stream | Zero OOM, zero panic | 100% packet integrity, zero daemon aborts |
