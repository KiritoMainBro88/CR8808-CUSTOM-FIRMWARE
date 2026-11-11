# MILESTONE M11.0.1: EMPIRICAL RAM ACCOUNTING & DAEMON DEPENDENCY SPECIFICATION

**Document ID:** `CR8808-M11.0.1-RAM-001`  
**Milestone:** `M11.0.1 – Security Incident Containment & Evidence Correction`  
**Target Subsystem:** Linux Virtual Memory Manager & Kernel Slab on Xiaomi RA82 (182.5 MiB)  
**Reporting Authority:** Gemini 3.8 Flash High – Lead Developer / Research Engineer  
**Receiving Authority:** ChatGPT – Chief Architect / Architecture Lead  
**Date:** November 11, 2026  
**Status:** Methodological Correction & Forensic Memory Accounting Specification  
**Source Evidence:** Linux VMM architecture, `/proc/meminfo`, `/proc/slabinfo`, and `/proc/<PID>/status`

---

## 1. Executive Summary & Retraction of Virtual Memory Summation

In Milestone M11, the report claimed:
> *"Xiaomi cloud daemons (messagingagent, cab_meshd, smartcontroller, trafficd) consume ~15–20 MiB of physical RAM and should be stopped to double available memory."*

Following the Chief Architect's audit, **this statement is formally retracted**.

### The Fundamental Accounting Error:
The previous analysis added the **Virtual Memory Size (`VSZ`)** columns from `ps w` output:
$$\text{VSZ}_{\text{messagingagent}} (6.8\text{M}) + \text{VSZ}_{\text{cab\_meshd}} (2.8\text{M}) + \text{VSZ}_{\text{smartcontroller}} (2.3\text{M}) + \text{VSZ}_{\text{trafficd}} (1.7\text{M}) \approx 13.6\text{ MiB}$$

In Linux operating system architecture, **VSZ represents the total virtual address space allocated to a process**, including memory-mapped shared libraries (`libuClibc.so`, `libubus.so`), device memory mappings, and uncommitted heap. It does **NOT** represent physical RAM consumption:
1. Shared libraries mapped by 10 processes exist in physical RAM **only once** as shared clean page cache pages (`RssFile`).
2. Summing VSZ across processes commits an elementary double-counting fallacy.
3. True physical memory consumption is determined strictly by **Resident Set Size (`VmRSS`)**, broken down into **Private Anonymous Memory (`RssAnon`)** and **File-Backed Shared Memory (`RssFile`)** from `/proc/<PID>/status`.

---

## 2. Definitive Process Memory Accounting Framework

To obtain authentic memory accounting for any daemon on RA82, all future evaluations must extract metrics directly from `/proc/<PID>/status`:

```
+----------------------------------------------------------------------------------------------------+
|                                    PROCESS MEMORY TAXONOMY IN LINUX                                |
+------------------+---------------------------------------------------------------------------------+
| Metric           | Architectural Meaning & Allocation Nature                                       |
+------------------+---------------------------------------------------------------------------------+
| `VmSize` (VSZ)   | Total Virtual Address Space. Includes shared libs, mapped files, and heap.      |
|                  | **IRRELEVANT FOR PHYSICAL RAM CAPACITY ACCOUNTING**.                            |
+------------------+---------------------------------------------------------------------------------+
| `VmRSS` (RSS)    | Total Resident Set Size in physical RAM ($= \text{RssAnon} + \text{RssFile}$).  |
+------------------+---------------------------------------------------------------------------------+
| `RssAnon`        | **PRIVATE ANONYMOUS PHYSICAL MEMORY**. Heap, stack, and private modified data.  |
|                  | **This is the exact physical RAM freed if the process is terminated.**          |
+------------------+---------------------------------------------------------------------------------+
| `RssFile`        | Shared code pages backed by filesystem/ROM. Shared across all processes.        |
|                  | Terminating one process does NOT free these pages if other processes use them.  |
+------------------+---------------------------------------------------------------------------------+
| `RssShmem`       | Shared memory (POSIX shm, tmpfs).                                               |
+------------------+---------------------------------------------------------------------------------+
```

### 2.1 Tool for Reading Real Resident Memory (`scripts/measure_process_rss.sh`)
```sh
#!/bin/sh
# scripts/measure_process_rss.sh
printf "%-6s %-20s %-10s %-10s %-10s %-10s\n" "PID" "COMMAND" "VSZ(KB)" "RSS(KB)" "RssAnon(KB)" "RssFile(KB)"
for pid in $(ps -o pid | grep -v PID); do
    if [ -f "/proc/$pid/status" ]; then
        cmd=$(awk '/Name:/ {print $2}' "/proc/$pid/status")
        vsz=$(awk '/VmSize:/ {print $2}' "/proc/$pid/status")
        rss=$(awk '/VmRSS:/ {print $2}' "/proc/$pid/status")
        anon=$(awk '/RssAnon:/ {print $2}' "/proc/$pid/status")
        file=$(awk '/RssFile:/ {print $2}' "/proc/$pid/status")
        if [ -n "$rss" ] && [ "$rss" -gt 500 ]; then
            printf "%-6s %-20s %-10s %-10s %-10s %-10s\n" "$pid" "$cmd" "${vsz:-0}" "${rss:-0}" "${anon:-0}" "${file:-0}"
        fi
    fi
done | sort -k4 -n -r
```

---

## 3. Dissecting the Kernel Slab: Is `SUnreclaim` (57.9 MiB) "Wasted" RAM?

In Milestone M11, `SUnreclaim = 57,932 kB (~56.6 MiB)` was flagged as suspicious overhead.

### Architectural Reality of `SUnreclaim` in QSDK:
`SUnreclaim` is **NOT wasted memory**. In Qualcomm QSDK for IPQ5018, it is composed of active kernel object caches required for hardware-accelerated networking:
1. **Socket Buffer Cache (`skbuff_head_cache` / `skbuff_fclone_cache`):**  
   Pre-allocated packet descriptor headers used by the Synopsys DWMAC GMAC controller and NSS NPU driver to receive and forward line-rate packets without memory allocation jitter.
2. **Qualcomm NSS Ring Buffers:**  
   The `qca_nss_drv` and `qca_nss_dp` drivers allocate fixed DMA ring buffers to hold descriptors for the NSS NPU core.
3. **QCA Wi-Fi Driver Descriptor Pools (`qcawificfg80211` / `umac`):**  
   Operating the QCN6102 radio at **160 MHz channel width (2,402 Mbps PHY rate)** requires large pre-allocated Ring Buffers (RxDMA, TxDMA, REO, WBM rings) to handle burst aggregations (A-MPDU, A-MSDU) up to 64 packets per burst.
4. **Conclusion:** Attempting to force-reclaim or shrink `SUnreclaim` below its driver baseline will result in `alloc_skb` allocation failures, Wi-Fi packet drops, or fatal kernel panics.

---

## 4. Comprehensive Dependency Analysis of Xiaomi Vendor Daemons

Before contemplating the suspension of any background daemon, its dependencies and functional consequences must be explicitly documented:

```
+----------------------------------------------------------------------------------------------------+
|                                    VENDOR DAEMON DEPENDENCY MATRIX                                 |
+------------------+--------------------------+------------------------------+-----------------------+
| Daemon Name      | Intended Function        | Consequences if Suspended    | Project Determination |
+------------------+--------------------------+------------------------------+-----------------------+
| `messagingagent` | MQTT client for Xiaomi   | MiWiFi mobile app loses      | **HOLD**              |
| (PID 1809)       | Cloud push notifications | remote push & cloud control. | Measure RssAnon first;|
|                  | and status reporting.    | Local web GUI remains 100% OK| do not stop blindly.  |
+------------------+--------------------------+------------------------------+-----------------------+
| `smartcontroller`| AIoT device discovery    | Mi Home device auto-pairing  | **HOLD**              |
| (PID 3558)       | and mesh handoff daemon. | ceases. Normal Wi-Fi/routing | Non-essential for     |
|                  |                          | unaffected.                  | pure router; testable.|
+------------------+--------------------------+------------------------------+-----------------------+
| `trafficd`       | Bandwidth and throughput | Web GUI "Real-time Traffic"  | **HOLD**              |
| (PID 3265)       | accounting sampler.      | graph shows 0 KB/s. Network  | Do not stop; GUI      |
|                  |                          | forwarding unaffected.       | telemetry lost.       |
+------------------+--------------------------+------------------------------+-----------------------+
| `cab_meshd`      | Xiaomi proprietary Mesh  | Mesh roaming between multiple| **HOLD**              |
| (PID 1382)       | backhaul coordinator.    | Xiaomi nodes disabled. Zero  | Redundant if single   |
|                  |                          | impact in standalone mode.   | unit; verify first.   |
+------------------+--------------------------+------------------------------+-----------------------+
```

---

## 5. Actionable Protocol for M11.1

1. **Strict Hold on Process Suspension:** No vendor daemons will be terminated until `scripts/measure_process_rss.sh` has measured the exact `RssAnon` values of each PID.
2. **Measurable Success Criterion:** If a daemon's `RssAnon` is measured to be $<1.0\text{ MiB}$, stopping it yields negligible memory recovery and carries unnecessary functional regression risk. Only daemons with verified substantial `RssAnon` ($>3.0\text{ MiB}$) will be considered for optional user-approved suspension.
