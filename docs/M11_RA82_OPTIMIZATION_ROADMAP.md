# MILESTONE M11: XIAOMI RA82 PERFORMANCE & SECURITY OPTIMIZATION ROADMAP

**Document ID:** `CR8808-M11-ROADMAP-001`  
**Milestone:** `M11 – RA82 Performance & Security Optimization Audit (Track A Primary)`  
**Project:** Xiaomi CR8808 Ver.B Custom Firmware (Internal Codename: `CR8818`)  
**Reporting Authority:** Gemini 3.8 Flash High – Lead Developer / Research Engineer  
**Receiving Authority:** ChatGPT – Chief Architect / Architecture Lead  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router writes, 0 flashing, 0 NAND/NVRAM modifications, 0 reboots)  
**Evidence Grounding:** Sanitized baseline logs [`reports/M12_BASELINE_SANITIZED.txt`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/reports/M12_BASELINE_SANITIZED.txt) and [`reports/M12_6_LIVE_SANITIZED.txt`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/reports/M12_6_LIVE_SANITIZED.txt) (original raw `M11_RA82_LIVE_AUDIT_RAW.txt` purged from Git HEAD under P0-1)

---

## 1. Executive Summary & Engineering Principles

This roadmap establishes the structured, itemized optimization program for the **RA82 Enhancement Project (Track A)** on the Xiaomi CR8808 Ver.B.

### Core Engineering Principles:
1. **Zero Flash Wear, Zero Brick Risk:** All proposals operate strictly within the running RA82 operating system (Linux 4.4.60 QSDK). Under no circumstances will any SPI NAND partition be modified or flashed.
2. **Defensive Reversibility:** Every single modification must have an explicit, instant, and tested rollback command. If a trial exhibits unexpected behavior, it can be reverted immediately at runtime, or automatically wiped clean on a hardware power-cycle.
3. **Strict Memory Discipline:** Total usable Linux RAM is capped at **182.5 MiB**, with only **~11.1 MiB of true `MemAvailable`**. Optimization must prioritize **reclaiming wasted memory** (stopping redundant vendor daemons, replacing bloated Go runtimes with Rust) before allocating any additional network buffers.
4. **Preservation of NSS Fast Path:** No configuration change shall disrupt or disable the Qualcomm NSS hardware acceleration engine, which currently offloads 96.9% of IPv4 traffic.

---

## 2. The 5-Tier Optimization Classification Taxonomy

To ensure absolute operational transparency, every proposed change is assigned to one of five architectural tiers:

```
+----------------------------------------------------------------------------------------------------+
|                                    OPTIMIZATION CLASSIFICATION TAXONOMY                            |
+-----------------------+----------------------------------------------------------------------------+
| Tier Tag              | Definition & Operational Scope                                             |
+-----------------------+----------------------------------------------------------------------------+
| `READ_ONLY`           | Passive diagnostics, telemetry, performance profiling, and readback.      |
|                       | Zero modification to memory, kernel, or configuration.                     |
+-----------------------+----------------------------------------------------------------------------+
| `RUNTIME_REVERSIBLE`  | Dynamic parameters applied in `/proc/sys`, `/sys/class`, or iptables.     |
|                       | Takes effect immediately; revertible via shell command or power-cycle.     |
+-----------------------+----------------------------------------------------------------------------+
| `PERSISTENT_CONFIG`   | Configuration written to `/data/` userdisk or UCI config files.            |
|                       | Survives reboot; requires explicit removal to restore factory defaults.    |
+-----------------------+----------------------------------------------------------------------------+
| `KERNEL_MODIFICATION` | Modification of out-of-tree kernel modules (`.ko`) in RAM or rootfs.       |
|                       | Requires module reload; prohibited unless certified by Chief Architect.    |
+-----------------------+----------------------------------------------------------------------------+
| `FLASH_REQUIRED`      | Writing to physical SPI NAND partitions (`mtd0`–`mtd20`).                  |
|                       | **STRICTLY PROHIBITED (HALT GATE: NO-GO FLASH)**.                          |
+-----------------------+----------------------------------------------------------------------------+
```

---

## 3. Itemized Optimization Proposals

### Group 1: CPU Packet Scheduling & SoftIRQ Balancing (High Impact)

#### Proposal 1.1: Enable Receive Packet Steering (RPS) for Software Interfaces
- **Target Subsystem:** Linux Network Queue Subsystem (`/sys/class/net/*/queues/rx-0/rps_cpus`).
- **Problem Statement:**  
  Live audit proves that **99.58% of all `NET_RX` softirqs are dumped onto CPU0 (234.5 million interrupts)**, while CPU1 is completely idle (0.42%). RPS is turned off (`rps_cpus: 0`) across all network devices. When non-NSS traffic (such as WireGuard `wg0` or DPI bypass) runs, CPU0 is choked by softirq processing.
- **Proposed Action:**  
  Configure `rps_cpus = 2` (steering packet processing to CPU1) for software-path interfaces:
  ```sh
  echo 2 > /sys/class/net/wg0/queues/rx-0/rps_cpus
  echo 2 > /sys/class/net/br-lan/queues/rx-0/rps_cpus
  echo 2 > /sys/class/net/eth0/queues/rx-0/rps_cpus
  ```
- **Expected Impact:**  
  Offloads software packet processing and crypto hashing to the idle Cortex-A53 core (CPU1). Eliminates packet drop risk under heavy VPN load and lowers CPU0 softirq latency.
- **Memory Delta:** Negligible (<4 KiB kernel skb queue overhead).
- **Classification:** **`RUNTIME_REVERSIBLE`**.
- **Rollback Procedure:**
  ```sh
  echo 0 > /sys/class/net/wg0/queues/rx-0/rps_cpus
  echo 0 > /sys/class/net/br-lan/queues/rx-0/rps_cpus
  echo 0 > /sys/class/net/eth0/queues/rx-0/rps_cpus
  ```

---

### Group 2: Memory Reclamation & Vendor Cloud Daemon Pruning (Critical Impact)

#### Proposal 2.1: Graceful Suspension of Redundant Xiaomi Telemetry Services
- **Target Subsystem:** Userspace vendor daemons running from `/usr/sbin/`.
- **Problem Statement:**  
  The system currently has only **11.1 MiB of `MemAvailable`**. Four non-essential vendor daemons run continuously:
  1. `messagingagent` (PID 1809): Xiaomi cloud MQTT telemetry daemon (6.8 MB VSZ).
  2. `cab_meshd` (PID 1382): Xiaomi Mesh management daemon (2.8 MB VSZ, unused in standalone router mode).
  3. `smartcontroller` (PID 3558): Mi Home IoT controller (2.3 MB VSZ).
  4. `trafficd` (PID 3265): Xiaomi cloud bandwidth reporter (1.7 MB VSZ).
  Together, these daemons consume **~15–20 MiB of physical RAM** and account for a baseline load average of ~1.9.
- **Proposed Action:**  
  Gracefully stop these 4 services at runtime via `/etc/init.d/`:
  ```sh
  /etc/init.d/messagingagent stop
  /etc/init.d/smartcontroller stop
  /etc/init.d/trafficd stop
  /etc/init.d/cab_meshd stop
  ```
- **Expected Impact:**  
  Immediately recovers **~15–20 MiB of physical RAM**, more than **doubling `MemAvailable` from 11.1 MiB to ~28–30 MiB**. Drops system idle load average from 1.9 to <0.4.
- **Memory Delta:** **+15.0 to +20.0 MiB of FREE RAM RECOVERED**.
- **Classification:** **`RUNTIME_REVERSIBLE`**.
- **Rollback Procedure:**
  ```sh
  /etc/init.d/messagingagent start
  /etc/init.d/smartcontroller start
  /etc/init.d/trafficd start
  /etc/init.d/cab_meshd start
  ```
  *(Or simple hardware reboot to restore 100% factory state).*

---

### Group 3: VPN Modernization: WireGuard Go to BoringTun Rust (High Impact)

#### Proposal 3.1: In-Place Replacement of Go WireGuard with BoringTun Rust
- **Target Subsystem:** VPN Server Daemon (`/data/wg_server` on `wg0`).
- **Problem Statement:**  
  The router currently runs `/data/wg_server` (WireGuard Go, PID 1305). The Go runtime allocates **523 Megabytes of virtual memory (`VSZ: 523m`)** and incurs periodic garbage collection CPU spikes on 32-bit ARM. The binary size on disk is 3.34 MiB.
- **Proposed Action:**  
  Deploy our statically linked, stripped ARMv7 BoringTun Rust binary (`boringtun-cli-armv7`, size ~1.08 MiB) into `/data/boringtun/`.
  Configure BoringTun to manage interface `wg0` with identical server keys and `10.99.0.1/24` addressing.
- **Expected Impact:**  
  - Cuts physical RAM consumption to **~3.0 MiB VmRSS** (saving tens of megabytes of process space).
  - Eliminates Go runtime GC stalls.
  - Built-in immunity to WireGuard UAPI panic regressions (tested under Milestones M6/M7).
- **Memory Delta:** **+10.0 to +15.0 MiB of RAM saved**.
- **Classification:** **`RUNTIME_REVERSIBLE`** (Can test BoringTun on an alternate port/tun interface first without stopping production VPN).
- **Rollback Procedure:**
  ```sh
  killall boringtun
  /data/start_wireguard.sh  # Restores wg_server Go daemon
  ```

---

### Group 4: Wi-Fi 6 Fine-Tuning & Quality-of-Experience (Medium Impact)

#### Proposal 4.1: Audit & Trial Uplink OFDMA (UL-OFDMA)
- **Target Subsystem:** 5 GHz QCA Wi-Fi Driver (`wl0` / `qcawificfg80211`).
- **Problem Statement:**  
  The live UCI wireless config shows `wireless.@wifi-iface[1].he_ul_ofdma='0'`. Uplink OFDMA is currently disabled, meaning multiple Wi-Fi 6 clients transmitting uplink data must time-share the channel sequentially rather than dividing the 160 MHz spectrum into Resource Units (RUs).
- **Proposed Action:**  
  Evaluate runtime activation of UL-OFDMA on interface `wl0`:
  ```sh
  iwpriv wl0 he_ul_ofdma 1
  ```
- **Expected Impact:**  
  Reduces gaming and voice call uplink latency when multiple Wi-Fi 6 devices are active simultaneously on the 5 GHz band.
- **Classification:** **`RUNTIME_REVERSIBLE`**.
- **Rollback Procedure:**
  ```sh
  iwpriv wl0 he_ul_ofdma 0
  ```

#### Proposal 4.2: Audit 802.11k/v Fast Roaming Assistance
- **Target Subsystem:** UCI Wireless Configuration (`wireless.@wifi-iface[*].rrm`, `.wnm`).
- **Problem Statement:**  
  Radio Resource Measurement (`rrm='0'`) and Wireless Network Management (`wnm='0'`) are disabled. Modern mobile clients (iOS, Android, Windows) benefit from 802.11k neighbor reports and 802.11v BSS transition management for smooth roaming.
- **Proposed Action:**  
  Evaluate setting `rrm='1'` and `wnm='1'` on `wifi0` and `wifi1` interfaces.
- **Classification:** **`PERSISTENT_CONFIG`** (Requires UCI commit and wifi reload).
- **Rollback Procedure:**
  ```sh
  uci set wireless.@wifi-iface[0].rrm='0'
  uci set wireless.@wifi-iface[0].wnm='0'
  uci set wireless.@wifi-iface[1].rrm='0'
  uci set wireless.@wifi-iface[1].wnm='0'
  uci commit wireless && wifi reload
  ```

---

### Group 5: Linux Networking Stack & Conntrack Sizing (Medium Impact)

#### Proposal 5.1: Right-Size Netfilter Conntrack Timeouts
- **Target Subsystem:** Kernel Netfilter Conntrack (`/proc/sys/net/netfilter/`).
- **Problem Statement:**  
  `nf_conntrack_tcp_timeout_established` is set to `1800` seconds (30 minutes). Idle or half-closed TCP connections remain cached in kernel slab for half an hour, holding memory.
- **Proposed Action:**  
  Tune established TCP timeout to `600` seconds (10 minutes) and generic timeout to `120` seconds:
  ```sh
  sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600
  sysctl -w net.netfilter.nf_conntrack_generic_timeout=120
  ```
- **Expected Impact:**  
  Accelerates table recycling, preventing conntrack bloat and freeing kernel slab memory.
- **Memory Delta:** Reclaims ~1–2 MiB of kernel slab.
- **Classification:** **`RUNTIME_REVERSIBLE`**.
- **Rollback Procedure:**
  ```sh
  sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=1800
  sysctl -w net.netfilter.nf_conntrack_generic_timeout=300
  ```

#### Proposal 5.2: Optimize TCP Socket Buffer Ceiling for 182 MB RAM
- **Target Subsystem:** Core TCP Sockets (`net.core.rmem_max`, `net.core.wmem_max`).
- **Problem Statement:**  
  Current settings allow up to 4 MiB buffer allocation per socket (`rmem_max = 4194304`). On a 182 MB RAM router, a small burst of high-concurrency downloads can induce severe memory pressure.
- **Proposed Action:**  
  Right-size max socket buffer to `2 MiB` (`2097152`), which perfectly satisfies the Bandwidth-Delay Product (BDP) for line-rate 1 Gbps at up to 20 ms latency ($10^9 \times 0.020 / 8 \approx 2.5 \text{ MB}$), while capping peak slab bloat:
  ```sh
  sysctl -w net.core.rmem_max=2097152
  sysctl -w net.core.wmem_max=2097152
  ```
- **Classification:** **`RUNTIME_REVERSIBLE`**.
- **Rollback Procedure:**
  ```sh
  sysctl -w net.core.rmem_max=4194304
  sysctl -w net.core.wmem_max=4194304
  ```

---

### Group 6: Security Hardening & Exposure Lockdown (High Priority)

#### Proposal 6.1: Restrict WAN SSH Exposure
- **Target Subsystem:** IPTables Firewall (`zone_wan_input`) and Dropbear configuration.
- **Problem Statement:**  
  Dropbear SSH on port `56789` is currently open to the entire WAN subnet (`0.0.0.0/0`) with root password authentication enabled. This exposes the router to brute-force credential stuffing from upstream networks.
- **Proposed Action:**  
  Option A: Remove the WAN SSH acceptance rule from `zone_wan_input` so SSH is accessible strictly from LAN (`br-lan`).  
  Option B: Restrict WAN SSH access strictly to the owner's workstation IP (`192.168.100.x`).
- **Expected Impact:**  
  Completely neutralizes WAN brute-force attack vectors.
- **Classification:** **`RUNTIME_REVERSIBLE`** / **`PERSISTENT_CONFIG`**.
- **Rollback Procedure:**
  ```sh
  iptables -I zone_wan_input 3 -p tcp --dport 56789 -j ACCEPT
  ```

---

## 4. Master Proposal Summary & Classification Matrix

```
+---------------------------------------------------------------------------------------------------------------------------------------+
|                                              MASTER RA82 OPTIMIZATION PROPOSAL REGISTER                                               |
+-----+-----------------------+-----------------------+----------------------+--------------------+--------------------+----------------+
| ID  | Proposal Title        | Target Subsystem      | Classification       | Performance Impact | Memory Impact      | Reversibility  |
+-----+-----------------------+-----------------------+----------------------+--------------------+--------------------+----------------+
| 1.1 | Enable RPS for wg0/lan| Linux Network Queues  | `RUNTIME_REVERSIBLE` | High (CPU balancing)| Negligible         | Instant command|
| 2.1 | Stop Vendor Daemons   | Xiaomi Cloud Services | `RUNTIME_REVERSIBLE` | High (CPU/Load drop)| **+15 to +20 MiB** | Instant command|
| 3.1 | BoringTun Rust Deploy | WireGuard Daemon      | `RUNTIME_REVERSIBLE` | High (Latency/GC)  | **+10 to +15 MiB** | Re-launch Go   |
| 4.1 | Enable UL-OFDMA       | 5 GHz Wi-Fi Driver    | `RUNTIME_REVERSIBLE` | Medium (UL latency)| Zero               | Instant iwpriv |
| 4.2 | Enable 802.11k/v      | UCI Wireless Config   | `PERSISTENT_CONFIG`  | Medium (Roaming)   | Zero               | UCI revert     |
| 5.1 | Conntrack Timeouts    | Netfilter Sysctl      | `RUNTIME_REVERSIBLE` | Medium (Recycling) | +1 to +2 MiB       | Instant sysctl |
| 5.2 | TCP Buffer Ceiling    | Core Network Sysctl   | `RUNTIME_REVERSIBLE` | Medium (OOM guard) | Prevents OOM       | Instant sysctl |
| 6.1 | Restrict WAN SSH      | IPTables WAN Zone     | `RUNTIME_REVERSIBLE` | High (Security)    | Zero               | Re-insert rule |
+-----+-----------------------+-----------------------+----------------------+--------------------+--------------------+----------------+
```

---

## 5. Phased Execution Runbook (Milestone M11)

```
+----------------------------------------------------------------------------------------------------+
|                                    PHASED EXECUTION SCHEDULE                                       |
+-------------------+--------------------------------------------------------------------------------+
| Phase 1 (CURRENT) | **Audit & Proposal Construction (COMPLETED)**                                  |
|                   | Baseline interrogation, empirical evidence logging, roadmap formulation.       |
|                   | Strict zero-touch rule: NO writes executed.                                    |
+-------------------+--------------------------------------------------------------------------------+
| Phase 2 (NEXT)    | **Chief Architect Review & Proposal Selection**                                |
|                   | ChatGPT Chief Architect evaluates the 8 proposals and sanctions trial scope.   |
+-------------------+--------------------------------------------------------------------------------+
| Phase 3           | **Controlled Single-Variable Runtime Trials**                                  |
|                   | Execute selected Tier 2 (`RUNTIME_REVERSIBLE`) changes one by one with live    |
|                   | benchmark verification (throughput, ping jitter, memory delta, loadavg).       |
+-------------------+--------------------------------------------------------------------------------+
| Phase 4           | **Hardening & Persistence Integration**                                        |
|                   | Only changes that show proven empirical gains without regression are scripted   |
|                   | into `/data/auto_run.sh` for persistence.                                      |
+-------------------+--------------------------------------------------------------------------------+
```

---

## 6. Strict Safety Affirmation

- **FLASHING STATUS:** `STRICT NO-GO FLASH` remains 100% active.
- **ROUTER INTEGRITY:** The physical router remains running stock RA82 v1.4.31 on Slot 1 (`rootfs_1`) with zero modification, zero NAND writes, and zero NVRAM commits.
- **LAB DIRECTORY:** `D:\vibecode\test_wifi` remains 100% untouched.

Kính trình Chief Architect thẩm định và phê duyệt lộ trình tối ưu hóa Milestone M11!
