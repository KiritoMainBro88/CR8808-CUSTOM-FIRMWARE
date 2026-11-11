# MILESTONE M10.1: SYSTEM RAM BUDGET & OOM DYNAMICS RECONCILIATION

**Document ID:** `CR8808-M10.1-RAM-001`  
**Milestone:** `M10.1 – Evidence Correction & Architecture Review`  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, 256MB DDR3L SDRAM)  
**Execution Authority:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)  
**Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router interaction, 0 SSH, 0 TFTP to router, 0 flashing, 0 NAND/NVRAM writes, 0 reboots)  

---

## 1. Executive Summary

This document provides a rigorous, tier-by-tier recalculation of the system memory architecture for the Xiaomi CR8808 Ver.B. In direct compliance with Chief Architect directives, this analysis:
1. Formally separates Physical Hardware RAM, Pre-Linux `no-map` reserved carveouts, Usable Linux `MemTotal`, and Operating Allocations.
2. Formally distinguishes between `MemFree` and `MemAvailable`.
3. Labels all projected operational allocations explicitly as **`ENGINEERING_ESTIMATE`**.
4. Completely rejects ungrounded claims of "OOM immunity", providing an honest engineering evaluation of memory pressure, failure boundaries, and kernel-level OOM mitigation strategies.

---

## 2. Multi-Tier Memory Decomposition

The Qualcomm IPQ5018 SoC on the CR8808 Ver.B is paired with a single 256 MiB (2,048 Mbit) DDR3L SDRAM chip operating at 1066 MHz. The physical address space starts at `0x40000000` and extends to `0x50000000`.

```
0x40000000                                                              0x50000000
+-------------------------+---------------------+-------------------------------+
|      LINUX MEMORY       | EARLY CARVEOUTS     |      HEXAGON Q6 WCSS          |
|    Usable MemTotal      | TZ/QTEE, SBL, SMEM  |      Reserved Carveout        |
|     (~182.0 MiB)        |     (10.0 MiB)      |          (48.0 MiB)           |
+-------------------------+---------------------+-------------------------------+
|<-------------------------- PHYSICAL RAM: 256.0 MiB -------------------------->|
```

### 2.1 Tier Breakdown Table

| Memory Tier | Classification | Base Address Range | Size (MiB) | Evidence Tier | Description / Authority |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Tier 0** | **Physical Hardware RAM** | `0x40000000` – `0x50000000` | **256.0** | `SOURCE_VERIFIED` | 256MB DDR3L soldered SDRAM |
| **Tier 1A** | **Hexagon Q6 WCSS Carveout** | `0x4b000000` – `0x4e000000` | **48.0** | `BUILD_VERIFIED` | DTB `wcss@4b000000` (`no-map`) |
| **Tier 1B** | **TrustZone / QTEE Secure OS**| `0x4a400000`, `0x4ac00000` | **6.0** | `BUILD_VERIFIED` | DTB `tz_apps` & `tz` (`no-map`) |
| **Tier 1C** | **Bootloader / SBL / SMEM** | `0x4a800000`, `0x4aa00000`, `0x4ab00000` | **4.0** | `BUILD_VERIFIED` | DTB `bootloader`, `sbl`, `smem` (`no-map`)|
| **Tier 1D** | **Early Kernel Bookkeeping** | Dynamic lowmem | **~16.0** | `ENGINEERING_ESTIMATE`| Kernel text, early page tables, memblock tracking |
| **Tier 2** | **Usable Linux `MemTotal`** | Dynamic high/lowmem | **~182.0** | `DEVICE_READBACK_RECONCILED` | Reported as ~186,400 kB in `/proc/meminfo` on stock RA82 |

### 2.2 Proof of `no-map` Exclusion
The device tree node `reserved-memory` extracted from the built firmware artifact (`artifacts/m10_images/extracted_cr8818.dts`, lines 132–169) explicitly marks all firmware carveouts with the **`no-map;`** attribute.

Under Linux kernel memory initialization (`arch/arm64/mm/init.c` and `drivers/of/fdt.c`):
- Any memory region carrying the `no-map` attribute is permanently detached from the kernel's buddy allocator during early boot (`early_init_fdt_scan_reserved_mem()`).
- The kernel does not create `struct page` tracking entries for these addresses.
- **Crucial Mathematical Conclusion:** The 48.0 MiB Q6 WCSS memory and 10.0 MiB security carveouts are **ALREADY SUBTRACTED** before the kernel computes `MemTotal`. There is zero double-counting against the ~182.0 MiB Linux memory.

---

## 3. Projected Operating Balance Sheet (`ENGINEERING_ESTIMATE`)

The table below details the projected memory allocations under a nominal dual-band Wi-Fi 6 production workload with active routing, firewall, and BoringTun WireGuard VPN.

> [!NOTE]  
> All figures in this section are classified as **`ENGINEERING_ESTIMATE`** derived from reference OpenWrt IPQ50xx deployments, driver specifications, and userspace process footprints. They do NOT represent physical silicon measurements, which remain blocked under `NO-GO FLASH`.

| Subsystem / Daemon | Memory Type | Projected RSS / Slab (MiB) | Evidence Tier | Technical Notes & Assumptions |
| :--- | :--- | :---: | :---: | :--- |
| **Linux Kernel Base** | Kernel Text & Core Data | 14.0 | `ENGINEERING_ESTIMATE` | Monolithic Linux 6.12.112 LTS image |
| **Kernel Slab & DMA** | kmalloc pools & sk_buffs | 18.0 | `ENGINEERING_ESTIMATE` | Network packet buffers, DSA tags, conntrack entries |
| **Wireless Driver (`ath11k`)**| Kernel module allocations | 16.0 | `ENGINEERING_ESTIMATE` | Mode 1 compact ring buffers (both 2.4G & 5G radios) |
| **Wi-Fi Daemon (`wpad`)** | Userspace RSS | 6.0 | `ENGINEERING_ESTIMATE` | `wpad-basic-mbedtls` hostapd dual-band AP management |
| **VPN Engine (`boringtun`)**| Userspace RSS | 10.0 | `ENGINEERING_ESTIMATE` | Rust userspace WireGuard engine (ring buffers & crypto) |
| **Core Daemons** | Userspace RSS | 16.0 | `ENGINEERING_ESTIMATE` | `procd`, `ubus`, `logd`, `netifd`, `dnsmasq`, `dropbear`, `firewall4` |
| **Web GUI (`luci`/`rpcd`)** | Userspace RSS | 8.0 | `ENGINEERING_ESTIMATE` | Active LuCI administrative sessions (transient) |
| **Total Projected Allocations**| Combined Runtime Footprint | **~88.0** | `ENGINEERING_ESTIMATE` | Peak nominal operational memory consumption |

---

## 4. `MemFree` vs `MemAvailable` Disambiguation

To ensure absolute precision in technical reporting, we formally delineate between `MemFree` and `MemAvailable`:

### 4.1 Definitions
1. **`MemFree` (Raw Unallocated Pages):**
   - The exact number of completely unallocated, idle 4 KiB physical page frames in the kernel buddy allocator (`nr_free_pages`).
   - Does NOT include page cache, dentries, or inode caches, even if they could be reclaimed immediately.
2. **`MemAvailable` (True Usable Headroom):**
   - A kernel heuristic estimate introduced in modern Linux kernels indicating how much memory is available for starting new applications without swapping.
   - Formula: $\text{MemAvailable} \approx \text{MemFree} + \text{Reclaimable PageCache} + \text{Reclaimable Slab} - \text{LowMem Watermark}$.

### 4.2 Projected Balance Under Nominal Load

$$\text{Usable Linux MemTotal} = 182.0\text{ MiB}$$
$$\text{Projected Active Allocations} \approx 88.0\text{ MiB (Nominal)}$$
$$\text{Estimated Net Headroom (MemAvailable)} \approx 94.0\text{ MiB} \quad (\pm 10\text{ MiB depending on pagecache})$$
$$\text{Estimated Raw MemFree} \approx 75.0\text{ MiB} \text{ to } 85.0\text{ MiB}$$

The previously reported figure of **92.0 MiB** is an **`ENGINEERING_ESTIMATE`** of `MemAvailable` under steady-state operation.

---

## 5. Realistic Out-Of-Memory (OOM) Dynamics & Failure Modes

> [!WARNING]  
> **REJECTION OF "OOM IMMUNITY"**  
> No embedded Linux router with 256 MB RAM and zero swap space is immune to Out-Of-Memory events. Any claim of unconditional OOM immunity on constrained silicon is technically invalid and rejected by this engineering team.

### 5.1 Critical OOM Trigger Conditions
On the CR8818, memory starvation can occur under three specific high-stress operating conditions:

1. **Massive Wi-Fi Client Load (> 64 Associated STAs per Radio):**
   - Each associated wireless station requires peer context state structures in `ath11k` kernel memory, BA (Block Ack) reordering windows, and per-station rate-control statistics.
   - If an AP experiences a surge of > 100 simultaneous STAs, `ath11k` slab allocations can expand by 20–30 MiB, severely squeezing available RAM.
2. **Conntrack Table Saturation (Deep NAT State Tracking):**
   - High-concurrency peer-to-peer (e.g. BitTorrent) or DDoS attacks opening tens of thousands of simultaneous UDP/TCP connections can exhaust `nf_conntrack` memory.
   - Each tracked connection consumes ~256 bytes of unpageable kernel slab memory. 32,768 connections consume ~8.5 MiB of critical lowmem.
3. **Userspace WireGuard (BoringTun) Buffer Bloat under UDP Saturation:**
   - Because BoringTun operates via userspace TUN devices (`/dev/net/tun`), packet processing requires copying packets across the kernel-userspace boundary.
   - Under heavy gigabit UDP bursts exceeding CPU encryption throughput, socket queue buffers and BoringTun internal channel queues can balloon userspace RSS by 15–25 MiB.

### 5.2 Architectural Defense-in-Depth Mitigations
To prevent fatal kernel panic or unhandled OOM killer invocations on production devices, the firmware integrates four defense mechanisms:

```
               SYSTEM OOM DEFENSE-IN-DEPTH ARCHITECTURE
               
  [ Hardware Level ]  ---> fw-memory-mode = <1> (Caps ath11k rings to 16MB)
                               |
  [ Kernel Level ]    ---> sysctl net.netfilter.nf_conntrack_max = 16384
                               |
  [ Memory VM Level ] ---> sysctl vm.min_free_kbytes = 4096 (Guarantees atomic DMA)
                               |
  [ Process Level ]   ---> procd oom_score_adj (Prioritizes LuCI/BoringTun over netifd)
```

1. **Enforced Low-Memory Profile (`fw-memory-mode = <1>`):**
   - Built directly into DTS `&wifi` and `&wifi1`. Caps DMA ring allocations and pre-allocated host memory.
2. **Conntrack Table Capping:**
   - Restricts `nf_conntrack_max` to 16,384 entries (capping slab consumption to ~4 MiB maximum).
3. **VM Watermark Protection (`vm.min_free_kbytes = 4096`):**
   - Configures the kernel to maintain a 4 MiB emergency pool reserved exclusively for atomic interrupt/DMA allocations (`GFP_ATOMIC`), preventing network driver panics.
4. **Hierarchical `oom_score_adj` Tuning:**
   - In the event of extreme exhaustion, the Linux OOM killer targets expendable processes first:
     - `luci` / `rpcd` / `uhttpd`: `oom_score_adj = +500` (First to be killed).
     - `boringtun-cli`: `oom_score_adj = +200` (VPN disconnects, but router survives).
     - `dnsmasq` / `dropbear`: `oom_score_adj = 0` (Preserved).
     - `netifd` / `procd` / `wpad`: `oom_score_adj = -1000` (Immune from OOM killer).

---

## 6. Evidence Classification & Taxonomy Compliance

| Memory Parameter | Value / Status | Evidence Tier | Verification Reference |
| :--- | :---: | :---: | :--- |
| Physical RAM | 256.0 MiB | `SOURCE_VERIFIED` | Hardware BOM & IPQ5018 memory bus spec |
| WCSS Carveout | 48.0 MiB | `BUILD_VERIFIED` | Extracted DTB `wcss@4b000000` (`no-map`) |
| TrustZone Carveout | 6.0 MiB | `BUILD_VERIFIED` | Extracted DTB `tz_apps` & `tz` (`no-map`) |
| Linux `MemTotal` | ~182.0 MiB | `DEVICE_READBACK_RECONCILED` | Stock Xiaomi RA82 `/proc/meminfo` readback (186,400 kB) |
| Runtime Operating Allocations | ~88.0 MiB | `ENGINEERING_ESTIMATE` | Projected itemized balance sheet |
| Net Available Headroom | ~94.0 MiB | `ENGINEERING_ESTIMATE` | Calculated $182.0 - 88.0\text{ MiB}$ balance |
| OOM Behavior Under Real Stress | Unverified | `UNVERIFIED` | Requires physical hardware stress-testing under Milestone M11 |

---

## 7. Conclusion & Sign-Off

The memory architecture has been fully reconciled:
- `no-map` attributes guarantee no double counting against Linux `MemTotal` (~182.0 MiB).
- Available operating headroom is an **`ENGINEERING_ESTIMATE`** of ~94.0 MiB.
- The firmware incorporates multi-tier OOM mitigations, while acknowledging that physical stability under heavy client/traffic stress remains an **`UNVERIFIED`** milestone item until real silicon validation.
