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
- BoringTun Rust operates with a deterministic, lightweight footprint (targeted `VmRSS < 15 MB` as `ACCEPTANCE_TARGET`, zero garbage collection pauses).

However, an essential technical distinction must be maintained regarding Qualcomm NSS hardware offload:
> [!IMPORTANT]
> **Silicon Cryptographic Limitation & Datapath Realities:**
> 1. The Qualcomm IPQ5018 SoC contains hardware crypto acceleration engines for **IPsec** (AES-CBC, AES-GCM, SHA1/256) and **DTLS**.
> 2. **The IPQ5018 does NOT possess hardware acceleration for ChaCha20-Poly1305** (the sole cipher suite utilized by the WireGuard protocol). Therefore, NSS **CANNOT** decrypt or encrypt WireGuard packets directly in hardware.
> 3. **ECM Offload Scope & Local Delivery:** Qualcomm ECM is architecturally designed to accelerate **forwarded NAT/routing flows** between network interfaces. Local-delivery packets terminating on a local host UDP socket (`ip_local_deliver` / `ip_local_out`) do not automatically receive NSS bypass; outer UDP stream acceleration for userspace-terminating VPN sockets is strictly **`UNVERIFIED`** on IPQ5018 silicon until empirical hardware measurement.
> 4. **Sole WireGuard Target:** BoringTun Rust is the sole WireGuard target engine for CR8818; Go WireGuard is legacy and will not be maintained.

This document formalizes the **Two-Tier Hybrid Acceleration Datapath**, delineating exactly which packet stages are handled by the host Cortex-A53 CPU using ARM NEON vector instructions, which stages traverse Linux kernel networking, and where NSS offload is theorized vs. unverified.

---

## 2. The Two-Tier Hybrid Acceleration Datapath

### 2.1 Inbound Datapath (Internet to LAN Host)

```
[ Internet / Remote WireGuard Peer ]
               |
  Encrypted UDP Datagram (Port 51821)
               v
     [ Physical WAN Port ]
               |
               v
+==================================================================================================+
| PHYSICAL & MAC LAYER (Synopsys DWMAC / stmmac / NSS Ingress Ring)                                |
|   - Physical frame reception, CRC/checksum check, L2 validation.                                 |
|   - Status: NSS outer UDP offload for local-delivery terminating socket is UNVERIFIED.           |
+===================================================+==============================================+
               |
               v
+==================================================================================================+
| LINUX KERNEL NETWORK STACK: LOCAL INGRESS                                                        |
|   - IP Ingress -> UDP layer (Port 51821 lookup) -> Linux UDP Socket Buffer (SO_RCVBUF)           |
+===================================================+==============================================+
               |
    recvmsg() / UDP Socket Read (Plain Socket API)
               v
+==================================================================================================+
| USERSPACE BORINGTUN RUST DAEMON (AArch64 musl / ARM NEON)                                        |
|   1. Reads encrypted UDP payload from Linux UDP Socket.                                          |
|   2. Poly1305 MAC Verification (ARM NEON SIMD accelerated).                                     |
|   3. ChaCha20 Stream Decryption (ARM NEON SIMD accelerated).                                     |
|   4. Plaintext IP Packet Extraction.                                                             |
|   5. Writes Decrypted Plaintext IP packet to /dev/net/tun.                                       |
+===================================================+==============================================+
               |
     write() to /dev/net/tun
               v
+==================================================================================================+
| LINUX KERNEL ROUTING & FORWARDING (Virtual wg1 / tun0 Interface)                                 |
|   1. Ingress from TUN driver -> Linux IP Routing Table Lookup.                                   |
|   2. Netfilter / nftables zone evaluation (VPN-to-LAN firewall policy, conntrack).               |
|   3. Egress Forwarding: Destination LAN subnet lookup.                                           |
|   4. Forwarded Flow Acceleration (ECM Classification):                                           |
|      - Clean Baseline: Handled by Linux in-kernel software flowtable (nftables flow_offload).    |
|      - NSS Offload (If active & interfaces supported): ECM installs L3 flow rule into NSS.       |
+===================================================+==============================================+
               |
               v
     [ Motorcomm YT9215SC Switch -> Destination LAN Host ]
```

### 2.2 Outbound Datapath (LAN Host to Internet)

```
[ LAN Host (e.g. 192.168.1.100) ]
               |
      Plaintext IP Packet
               v
+==================================================================================================+
| LINUX KERNEL ROUTING & FIREWALL                                                                  |
|   1. Ingress from LAN interface (br-lan).                                                        |
|   2. Linux Routing Table evaluates route -> matches WireGuard subnet -> egress to wg1 (TUN).     |
|   3. Netfilter / nftables evaluates outbound policy.                                             |
|   4. Linux TUN driver places packet in /dev/net/tun read queue.                                  |
+===================================================+==============================================+
               |
     read() from /dev/net/tun
               v
+==================================================================================================+
| USERSPACE BORINGTUN RUST DAEMON (AArch64 musl / ARM NEON)                                        |
|   1. Reads plaintext IP packet from /dev/net/tun.                                                |
|   2. Route / Peer Matching (AllowedIPs lookup).                                                  |
|   3. ChaCha20 Stream Encryption (ARM NEON SIMD accelerated).                                     |
|   4. Poly1305 MAC Authentication Tag Generation (ARM NEON SIMD).                                 |
|   5. Encapsulates into UDP Datagram (destination peer IP:port).                                  |
|   6. Sends datagram via Linux UDP socket: sendto() / sendmsg().                                  |
+===================================================+==============================================+
               |
     sendto() via Linux UDP Socket
               v
+==================================================================================================+
| LINUX KERNEL NETWORK STACK: LOCAL EGRESS                                                         |
|   - UDP Socket output -> IP Egress routing -> Netfilter POSTROUTING (NAT/masquerade if needed)   |
|   - Transmitted out through WAN interface (eth0/eth1).                                           |
|   - Note: Acceleration of local socket egress by ECM is UNVERIFIED on IPQ5018.                   |
+===================================================+==============================================+
               |
               v
     [ Physical WAN Port -> Internet Gateway ]
```

---

## 3. Detailed Division of Labor: NSS vs. Host CPU

| Datapath Stage | Responsible Processing Entity | Acceleration Mechanism & Characteristics |
|---|---|---|
| **Outer WireGuard UDP Socket Delivery** | **Linux Kernel UDP Stack / NSS (Unverified)** | **`UNVERIFIED` Hardware Offload:** Qualcomm ECM accelerates forwarded NAT flows. Whether outer UDP sockets terminating in userspace bypass software netfilter without CPU exception is unverified on IPQ5018. |
| **ChaCha20 Decryption / Encryption** | **Host CPU (Cortex-A53)** | **SIMD Accelerated:** Vectorized using ARM NEON instructions (zero hardware NPU offload). |
| **Poly1305 MAC Verification / Tagging**| **Host CPU (Cortex-A53)** | **SIMD Accelerated:** Vectorized polynomial arithmetic in BoringTun Rust. |
| **Inner Tunnel Forwarding (wg1 <-> LAN)** | **Linux Kernel / NSS ECM** | **Forwarded NAT Flow:** Plaintext forwarded flows between `wg1` and `br-lan` can be offloaded by software flowtable (Clean Baseline) or programmed into NSS via ECM if virtual interfaces are supported. |
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
| **Resident Memory (RSS)** | `grep -i vmrss /proc/<pid>/status`| Kilobytes (KB) | `ACCEPTANCE_TARGET` (< 15,000 KB targeted; unverified until live benchmark) |
| **Peak Memory (HWM)** | `grep -i vmhwm /proc/<pid>/status`| Kilobytes (KB) | Record maximum resident watermark |
| **Latency Under Load (P50/P95/P99)**| `ping -i 0.2 -c 500 <peer>` | Milliseconds (ms) | Compare P99 latency against Go baseline |
| **SoftIRQ Overhead** | `/proc/softirqs` (NET_RX / NET_TX) | Rate (interrupts/sec) | Confirm NAPI behavior under load |
| **Long-Term Soak Stability** | 4-hour continuous 50 Mbps stream | Zero OOM, zero panic | 100% packet integrity, zero daemon aborts |
