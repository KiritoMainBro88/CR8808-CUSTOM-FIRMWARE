# Memory Engineering & Stability Validation: 256 MB RAM Profile for IPQ5018 & NSS

- **Document ID:** `docs/NSS_256MB_MEMORY_VALIDATION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Qualcomm IPQ5018 + 256 MB DDR3L RAM)
- **Target Platform:** OpenWrt Mainline / Linux Kernel 6.18 (AArch64 musl)
- **Scope:** Rigorous Memory Budgeting, DTS Carve-Outs, Kernel Low-Memory Profiles, and Pressure Telemetry
- **Status:** Architectural Specification & Memory Validation Plan

---

## 1. Executive Summary & Physical Hardware Realities

Operating modern Linux kernel 6.18, Qualcomm NSS hardware offload, dual-band Wi-Fi 6 (`ath11k` HE160), and WireGuard on a router with **256 MB physical DDR3L RAM** is one of the most constrained environments in enterprise networking:
- **Total Physical RAM:** 256 MB (268,435,456 bytes).
- **Usable Linux RAM (`MemTotal`):** **~182 MB** (`186,816 kB` as measured in stock router interrogation).
  - Qualcomm TrustZone (QSEE / secure OS) reserves ~32 MiB at top of physical memory.
  - U-Boot, TZ carve-outs, and shared hardware queues claim ~42 MiB before the Linux kernel boots.
- **The Core Risk:** In standard OpenWrt enterprise profiles (designed for 512 MB – 1 GB devices), NSS buffer pools allocate 24–32 MiB, while `ath11k` descriptor rings allocate ~20 MiB of contiguous DMA slab. On a 182 MB usable system, standard profiles leave virtually zero headroom for userland daemons, leading to immediate OOM killer invocations or packet buffer starvation.

This document grounds our memory architecture in the proven **256 MB Profile published by `kuncy7`**, corrects earlier speculative memory figures, and establishes empirical memory pressure metrics.

---

## 2. The Authoritative Kuncy 256 MB Memory Profile Audit

Community developer `kuncy7` (`kuncy7/openwrt-nss-edma`) maintains the primary working reference for running IPQ5018 on Linux 6.18 with 256 MB RAM (supporting devices like `cudy_p5`, `ruijie_rg-ma3063`, and `xiaomi_cr8806`).

### 2.1 The Specific Low-Memory Configuration:

| Configuration Parameter | Value in 256 MB Profile | Default Enterprise Value | Memory Saved / Rationale |
|---|---|---|---|
| **DTS `nss_region` Reservation** | **`8 MiB`** (`0x800000`) | 16–32 MiB | **Saves 8–24 MiB.** Pinned DRAM reserved exclusively for NSS NPU firmware text, data, and internal heap. |
| **NSS Buffer Pool Profile** | **`MP_256` / `NSS_MEM_PROFILE_LOW=y`** | Standard / High | **Saves ~12–16 MiB.** Restricts `qca-nss-pbuf` pre-allocated network packet buffer pool to ~8–12 MiB. |
| **Wi-Fi Ring Buffers** | **`ATH11K_MEM_PROFILE_256M=y`** | Standard (1024 rings) | **Saves ~16–20 MiB.** Restricts TX/RX descriptor rings from 1024 to 256 or 512 descriptors per radio. |
| **Coherent DMA Pool** | **`coherent_pool=512k`** | 2M – 4M | **Saves 1.5–3.5 MiB low-memory.** Requires patch 0828 to operate safely without DMA slab failure. |
| **Kernel Patch 0828** | **`0828-arm64-dts-ipq5018-adjust-coherent-pool.patch`** | None | Enforces atomic pool allocation boundaries specifically tuned for IPQ5018 DWMAC descriptors. |

### 2.2 Correction of DTS `nss_region` Carve-Out:
Earlier drafts of our project documentation loosely estimated `nss_region` at 12–16 MiB.
- **Correction:** The authoritative Kuncy DTS node specifies exactly **8 MiB** (`0x800000`):
```dts
reserved-memory {
    nss_region: nss@40000000 {
        reg = <0x0 0x40000000 0x0 0x800000>; /* Exactly 8 MiB */
        no-map;
    };
};
```
Setting `nss_region` higher than 8 MiB unnecessarily robs the Linux page allocator of general-purpose RAM. Setting it lower than 8 MiB may prevent NSS 12.5 firmware (`retail_router0.bin`) from initializing. Note: The 8 MiB carve-out must be cross-checked against the specific NSS firmware release binary used during image generation.

---

## 3. Disambiguating Memory Metrics: VmSize vs. VmRSS vs. Buddyinfo

A critical finding from our architecture review is that prior performance analyses misdiagnosed memory pressure by confusing virtual address allocations with physical RAM usage:

### 3.1 Virtual Memory (`VmSize`) vs. Resident Set Size (`VmRSS`):
- **`VmSize` (Virtual Memory Size):** Measures the total address space mapped by a process (including uncommitted pages, shared libraries, mmap regions, and thread stack address spaces). In garbage-collected runtimes like Go, the runtime pre-reserves large virtual address arenas (e.g. 522 MB).
- **`VmRSS` (Resident Set Size):** Measures the **actual physical RAM pages** currently resident in hardware DRAM.
- **Empirical Correction:** A Go process with `VmSize = 522 MB` and `VmRSS = 3.7 MB` occupies **only 3.7 MB of physical RAM**. Comparing 522 MB to 182 MB physical RAM and concluding that Go causes memory exhaustion is scientifically invalid.

### 3.2 High-Order Pages vs. 4 KB Single Pages in `buddyinfo`:
- Linux kernel `/proc/buddyinfo` tracks free page blocks grouped by order ($2^{\text{order}} \times 4\text{ KB}$).
- Absence of high-order chunks (Order 8–10: 1 MB – 4 MB continuous blocks) indicates normal physical memory fragmentation, but does **NOT** prove memory exhaustion.
- Network packet buffers (`sk_buff` payload) and general userspace allocations use Order-0 (single 4 KB pages) or slab caches (`kmalloc-512`, `kmalloc-2048`), which succeed as long as Order-0 pages remain available.

### 3.3 True Indicators of Severe Memory Pressure:
To scientifically determine whether the CR8818 is under memory pressure, monitoring must target the following kernel counters in `/proc/vmstat` and `/proc/meminfo`:
1. **`allocstall`:** Increments when the kernel page allocator blocks because no free pages are available, forcing direct reclaim. High `allocstall` indicates imminent freeze.
2. **`pgscan_kswapd` vs. `pgscan_direct`:** If `pgscan_direct` rises rapidly, `kswapd` is unable to keep up in the background, causing latency spikes in network processing.
3. **`pgsteal`:** Measures actual pages reclaimed. If `pgscan` is high but `pgsteal` is low, the system is thrashing.
4. **`oom_killer` Invocations:** Kernel logs showing `Out of memory: Kill process` or `nss_alloc_pbuf_failed`.

---

## 4. The NSS 12.5 Buffer Starvation Anomaly (Release 2026.11.09)

In the official release notes of `kuncy7/openwrt-nss-edma` (dated 09/11/2026), a critical defect is documented:
- **Symptom:** Under conditions of heavy Wi-Fi packet retransmissions (e.g. multiple clients at edge of coverage with low SNR), NSS 12.5 buffer descriptors can stall or leak in flight without timely deallocation back to the free pool.
- **Impact on 256 MB Devices:**
  - On 512 MB / 1 GB routers, the large buffer pool absorbs transient leaks without exhausting the system.
  - On 256 MB devices with the `MP_256` profile (~8–12 MiB pool), buffer exhaustion occurs rapidly.
  - When the NSS packet buffer pool hits zero, **all wired Ethernet traffic completely freezes / stalls**, requiring a hard reboot.
- **Evidence Demarcation:** The author noted that this bug was **user-reported and unreproduced by the author**, and that **256 MB targets were not tested** during that release cycle.
- **Mitigation Directive:** This hazard reinforces our mandate that Phase 1 Clean DSA remains the stable production baseline, and Phase 2 NSS porting must undergo extensive Wi-Fi retransmission stress testing before any consideration of deployment.

---

## 5. Realistic Physical DRAM Budget Breakdown (Total ~182 MB)

Grounded in the verified Kuncy 256 MB profile and BoringTun Rust:

```mermaid
pie title Grounded Usable DRAM Budget (Total ~182 MB)
    "Linux Kernel & Core Slab" : 85
    "NSS Firmware (nss_region 8M)" : 8
    "qca-nss-pbuf Buffer Pool (MP_256)" : 10
    "ath11k DMA Rings (256M Profile)" : 18
    "BoringTun Rust Daemon (Peak RSS)" : 15
    "Userspace Daemons & LuCI" : 20
    "Free Safety Headroom (Buffer/Cache)" : 26
```

### Numerical Allocation Table:
- **Linux Kernel Core, Slab, Page Tables:** ~85 MB
- **Qualcomm NSS Firmware Pinned Region (`nss_region`):** 8 MB
- **Qualcomm NSS Packet Buffer Pool (`qca-nss-pbuf` MP_256):** ~10 MB
- **`ath11k` Wi-Fi DMA Rings & Buffers (`ATH11K_MEM_PROFILE_256M`):** ~18 MB
- **BoringTun Rust Userspace Daemon (Peak RSS):** <15 MB (`ACCEPTANCE_TARGET`; unverified until live physical benchmark)
- **Core Userspace Daemons (`procd`, `ubus`, `netifd`, `dropbear`, `dnsmasq`, `hostapd`):** ~20 MB
- **Total Committed Memory:** **~156 MB**
- **Free Headroom for Page Cache / Ephemeral Sockets:** **~26 MB (14.3% safety margin)**.

This confirms that with the strict 256MB profile, system operation is mathematically viable, but leaves minimal margin for unoptimized software or memory leaks.
