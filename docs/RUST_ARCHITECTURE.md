# Architectural Strategy: C + Rust Hybrid Userspace Strategy for Xiaomi CR8808 Ver.B

- **Document ID:** `docs/RUST_ARCHITECTURE.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 @ 1.0 GHz + NSS NPU, 256MB DDR3L, 128MB SPI NAND)
- **Target OS:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Author:** Gemini Engineering Team (Implementer / System Operator)
- **Reviewer:** ChatGPT Architecture Lead
- **Status:** Architectural Specification & Strategy Directive Implementation

---

## 1. Executive Summary & Strategic Rationale

Following the completion and review of Milestone M4 (Kbuild audit, Option A/B separation, and switch register validation), this document formalizes the **Rust-First Userspace Strategy** for the Xiaomi CR8808 Ver.B custom firmware.

The project firmly rejects language dogma on both extremes:
1. **Against "C-Everywhere" Inertia:** We reject the premise that userspace networking services on embedded Linux must remain written in legacy C or heavy, garbage-collected runtimes (such as Go). Memory corruption vulnerabilities (buffer overflows, use-after-free, double-frees) in userspace daemons represent the majority of remote code execution CVEs in commercial router firmware.
2. **Against "Rewrite-the-Kernel-in-Rust" Trends:** We reject the impulse to rewrite existing, working Linux kernel drivers in Rust merely because Rust is a trending language. The Linux Distributed Switch Architecture (DSA), Qualcomm NSS/NSS-DP, Motorcomm switch drivers, and kernel network stacks are deeply rooted in C APIs. Rewriting them provides negligible security gain at the hardware boundary while introducing severe risks of regressions, unmaintainable out-of-tree bindings, and kernel compilation fragility.

The CR8808 firmware adopts a deliberate **C + Rust Hybrid Architecture**, strictly delineating responsibilities based on silicon interfaces, safety requirements, and performance characteristics.

---

## 2. Strict Division of Labor by Subsystem

| Firmware Subsystem | Language | Implementation & Role | Technical Justification |
|---|---|---|---|
| **Qualcomm NSS / NSS-DP** | **C** | `qca-nss-drv`, `qca-nss-dp`, `qca-nss-ecm`, `qca-nss-clients` | Silicon vendor firmware interfaces and kernel offload shims. Built on Qualcomm C APIs. Direct hardware register and IPC ring interaction. |
| **Switch Subsystem** | **C** | Motorcomm `yt921x.c`, `yt921x_8021q.c`, `tag_yt921x.c` | Linux DSA subsystem architecture operates exclusively via C callbacks (`dsa_switch_ops`, `tag_ops`). MDIO register access is inherently C-based. |
| **Ethernet MAC & DMA** | **C** | Synopsys DWMAC (`stmmac`), Qualcomm IPQ5018 DWMAC glue | Core kernel networking DMA rings, IRQ handling, and NAPI polling. Upstream Linux driver is C. |
| **Hardware Description** | **DTS** | `ipq5018-cr8818.dts`, `ipq5018-cr881x-nss.dts` | Standard Devicetree Source for SoC pinmux, clocks, MDIO busses, and memory reserved regions. |
| **Wi-Fi Subsystem** | **C** | Upstream Linux `ath11k` + mac80211 | Upstream Qualcomm Wi-Fi driver supporting IPQ5018 2x2 2.4 GHz + QCN6102 2x2 5 GHz HE160. |
| **WireGuard Engine** | **Rust** | **Cloudflare BoringTun 0.7.1** (`boringtun-cli`) | **Sole WireGuard target engine.** Zero GC pauses, deterministic resident memory (`VmRSS < 15 MB`), memory-safe packet handling, ARM NEON SIMD crypto (`ring`, `chacha20poly1305`). Completely replaces `wireguard-go`. |
| **System Telemetry & Health** | **Rust** | `cr8818-monitor` (Unified Daemon) | Collects CPU, RAM, and NSS statistics with zero memory allocation churn. Provides watchdog heartbeats and automated recovery. |
| **Configuration Validator** | **Rust** | `cr8818-cfgval` (CLI Tool) | Pre-commit syntax, schema, and safety validator for UCI network and firewall configurations to prevent remote lockouts. |
| **Testing & Verification** | **Rust + C** | Independent C Oracle (`tests/poc/`) + Rust Fuzzing Suite (`tests/rust_verification/`) | Dual-language validation: C verifies bit-for-bit kernel wire vectors; Rust executes property-based testing, fuzzing, and UAPI state machine validation. |

---

## 3. Detailed Technical Rationale

### 3.1 Why Linux Kernel Drivers Must Remain in C

Attempting to rewrite the IPQ5018 kernel components in Rust violates core engineering pragmatism:

1. **Subsystem API Compatibility:**
   - The Linux DSA framework (`include/net/dsa.h`), `ethtool_ops`, and `phylink` APIs are designed around C structures, function pointers, and macros.
   - Rust-for-Linux (`CONFIG_RUST`) in mainline Linux 6.18 primarily provides abstractions for character devices, basic PCI/platform drivers, and synchronization primitives. There is **zero upstream Rust binding for DSA switch drivers or network taggers**.
   - Writing custom, out-of-tree C-to-Rust shims for DSA would create a fragile maintenance burden larger than the driver itself (~1,200 lines of C for `yt921x.c`).

2. **Qualcomm NSS Proprietary Interop:**
   - The Qualcomm NSS ecosystem (`qca-nss-drv`) communicates with the closed-source NSS NPU firmwares (`retail_router0.bin`) via complex shared memory queues and C structures defined in Qualcomm-specific headers.
   - The NSS Data Plane (`qca-nss-dp`) hooks directly into the Synopsys DesignWare MAC (`stmmac`) via C function pointers (`nss_dp_override_ops`).
   - Introducing Rust bindings at this boundary would destabilize the delicate timing, DMA memory barriers, and cache coherency operations of the 256MB memory profile.

3. **Risk vs. Return on Kernel Code:**
   - The switch driver and DSA tagger execute in kernel space and are ~2,000 lines of code total. Their correctness is thoroughly provable through static analysis and our oracle test harness (84/84 C tests passed in M4).
   - Rewriting them in Rust would introduce foreign build dependencies (`rustc` during kernel Kbuild, `bindgen`, `libclang`) and risk build breakage across OpenWrt kernel minor updates.

### 3.2 Why Userspace Components Excel in Rust

In userspace, the trade-offs invert entirely in favor of Rust:

1. **Elimination of Remote Memory Corruption:**
   - Userspace daemons processing untrusted network packets (VPN tunnels, health telemetry endpoints, web APIs) are exposed to remote adversaries.
   - Rust guarantees spatial and temporal memory safety at compile time: no buffer overflows, no dangling pointers, no double frees, and zero data races across OS worker threads.

2. **Elimination of Garbage Collection Overhead (Rust vs. Go):**
   - The stock OpenWrt userspace WireGuard implementation (`wireguard-go`) uses the Go runtime.
   - Go's memory allocator pre-allocates large virtual memory arenas (`VmSize` often exceeds 500 MB on AArch64) and triggers periodic garbage collection (GC) sweeps that pause execution and induce latency spikes.
   - On a memory-constrained 256MB router (where Linux `MemTotal` is only ~182 MB), a Go daemon poses severe OOM risks.
   - Rust uses RAII (Resource Acquisition Is Initialization) with deterministic stack/heap management and zero runtime GC. BoringTun operates with an idle `VmRSS` of ~3.8 MB and a peak under-load `VmRSS < 15 MB` (`ACCEPTANCE_TARGET`).

3. **ARM NEON SIMD Vector Acceleration:**
   - ChaCha20-Poly1305 encryption/decryption is computationally intensive.
   - Rust cryptography crates (`ring`, `chacha20poly1305`, `curve25519-dalek`) compile directly to optimized ARM NEON SIMD vector instructions on the Cortex-A53 CPU.
   - By leveraging Rust's compiler intrinsics and LLVM vectorizer, BoringTun achieves near-line-rate userspace cryptographic throughput without requiring in-kernel cryptographic drivers.

---

## 4. Architectural Boundaries and System Call Interface

```
+==================================================================================================+
|                                    USERSPACE (RUST RUNTIME)                                      |
+==================================================================================================+
|                                                                                                  |
|   +------------------------------------+          +------------------------------------------+   |
|   |   BoringTun Rust Daemon (wg0)      |          |    cr8818-monitor System Daemon          |   |
|   |   - AArch64 musl (statically linked)|          |    - Telemetry collector (/proc, /sys)   |   |
|   |   - ChaCha20-Poly1305 (ARM NEON)   |          |    - Memory pressure watcher (<25MB)     |   |
|   |   - Zero-GC, VmRSS < 15 MB         |          |    - Hardware watchdog heartbeat         |   |
|   |   - UAPI Socket: /var/run/wireguard|          |    - Automated procd restart triggers    |   |
|   +-----------------+------------------+          +--------------------+---------------------+   |
|                     |                                                  |                         |
+=====================|==================================================|=========================+
|                     | System Calls: read(), write(), ioctl(), poll()   | open(), read(), ioctl() |
+=====================|==================================================|=========================+
|                     v                                                  v                         |
|   +------------------------------------+          +------------------------------------------+   |
|   | Virtual TUN Driver (/dev/net/tun)  |          | Kernel Procfs & Sysfs Interfaces         |   |
|   | - Plaintext IP packets ingress     |          | - /proc/meminfo, /proc/stat              |   |
|   | - Tunnel socket egress             |          | - /dev/watchdog0 hardware timer          |   |
|   +-----------------+------------------+          +------------------------------------------+   |
|                     |                                                                            |
+=====================|============================================================================+
|                     v                                                                            |
|        [ Linux Kernel Network Stack (Netfilter / nftables / IP Routing) ]                        |
|                                     |                                                            |
|                                     v                                                            |
|        [ Qualcomm ECM (Enhanced Connection Manager - L3 Flow Offload) ]                          |
+=====================================|============================================================+
|                                     |                                                            |
+=====================================|============================================================+
|                                     v                                                            |
|                           LINUX KERNEL DRIVERS (C)                                               |
+==================================================================================================+
|   - Qualcomm NSS Core Driver (`qca-nss-drv.ko`)                                                  |
|   - Qualcomm NSS Data Plane (`qca-nss-dp.ko` / `qca-dwmac-nss.ko`)                               |
|   - Motorcomm YT9215SC DSA Switch Driver (`yt921x_8021q.c` / `yt921x.c`)                         |
|   - Synopsys DesignWare MAC Driver (`dwmac-ipq5018.c`)                                           |
|   - Qualcomm Wi-Fi Driver (`ath11k` / `mac80211`)                                                |
+=====================================|============================================================+
|                                     v                                                            |
+==================================================================================================+
|                              HARDWARE & SILICON LAYER                                            |
+==================================================================================================+
|   - Qualcomm IPQ5018 SoC (Dual Cortex-A53 @ 1.0 GHz + NSS NPU @ 1.0 GHz)                         |
|   - Motorcomm YT9215SC 5-Port Gigabit Switch (MDIO @ 0x00)                                       |
|   - 256 MB DDR3L RAM (182 MB Linux usable + 42 MB NSS Reserved + 32 MB System Reserved)          |
+==================================================================================================+
```

---

## 5. Rust System Services Strategy & Evaluation

To prevent RAM fragmentation on the 256MB memory profile, we enforce strict criteria before any userspace service is approved for Rust implementation:

### 5.1 Service Evaluation Matrix

| Proposed Service | Suitability | Flash Footprint | RAM Footprint (RSS) | Final Determination |
|---|---|---|---|---|
| **BoringTun (WireGuard)** | **Mandatory** | ~1.4 MB (stripped static) | ~3.8 MB idle / <15 MB load | **APPROVED** — Replaces high-overhead `wireguard-go`. Sole VPN engine. |
| **Unified Telemetry & Watchdog (`cr8818-monitor`)** | **High** | ~350 KB | ~1.2 MB | **APPROVED** — Replaces fragmented shell scripts with single zero-alloc daemon. |
| **Config Validator (`cr8818-cfgval`)** | **High** | ~280 KB | Ephemeral CLI (0 MB resident) | **APPROVED** — Pre-commit validator run before applying UCI network changes. |
| **HTTP/REST API Daemon** | **Low** | ~4-8 MB (Tokio/Axum) | ~15-25 MB | **REJECTED** — Excessive memory overhead. OpenWrt `uhttpd` / `rpcd` (C) is retained. |
| **Custom DNS/DHCP Server** | **Low** | ~3-5 MB | ~10-20 MB | **REJECTED** — Upstream `dnsmasq` (C) is proven, highly optimized, and uses <2 MB RSS. |
| **Routing Protocol Daemon (BGP/OSPF)** | **Low** | ~6-12 MB | ~20-40 MB | **REJECTED** — `frr` / `bird` (C) are upstream-managed. No justification. |

### 5.2 Architectural Rules for Userspace Rust Services

1. **No Tokio Async Runtime for Simple daemons:** Standard blocking I/O with `poll()` or `epoll` via lightweight crates (e.g. `mio` or standard library) must be used instead of full-featured asynchronous runtimes like Tokio to keep binary size under 500 KB and RSS under 2 MB.
2. **Consolidated Daemons:** Monitoring, watchdog pinging, and VPN tunnel telemetry must be compiled into a single unified binary (`cr8818-monitor`) with multiple thread workers rather than running 3 separate daemons.
3. **No Unpinned Dependencies:** All Rust dependencies must be pinned by exact version in `Cargo.lock` and vendored in source tarballs.
4. **Zero Compiler on Device:** The Rust compiler (`rustc`) and `cargo` must never be packaged into the OpenWrt firmware image. All binaries are cross-compiled on the PC build host.
