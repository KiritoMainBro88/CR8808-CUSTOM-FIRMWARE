# M11.1 R0 Live Baseline Audit Report — Empirical Hardware Telemetry

- **Document ID:** `reports/M11_1_R0_LIVE_BASELINE_REPORT.md`
- **Target Device:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Active System:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit `armv7l`)
- **Interrogation Method:** Class R0 Pure Read-Only SSH via [`scripts/m11_1_r0_baseline_audit.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/m11_1_r0_baseline_audit.sh)
- **Safety Boundary:** **CLASS R0 | ZERO CONFIG MODIFICATIONS | ZERO FLASH/NVRAM WRITES | ZERO REBOOTS**
- **Date/Time:** 2026-11-11 23:56:56 +07:00 (Revised under Architecture Directive M11.1.0.1)
- **Status:** **R0 LIVE BASELINE CORRECTED — PREFLIGHT GATED**

---

## 1. Executive Summary & Storage Boundary Clarification

Pursuant to the User / Chief Architect Directives M11.1 and M11.1.0.1:
> *"Cho phép Gemini bắt đầu M11.1 – R0 Live Baseline, tức SSH vào router nhưng chỉ chạy đúng danh sách lệnh đọc dữ liệu trong docs/R0_READONLY_AUDIT_MANIFEST.md. Chưa cho phép thay đổi cấu hình router."*

### 1.1 Storage Boundary Demarcation (Correction)
- **Persistent Flash Storage (NAND / NVRAM / MTD):** **ABSOLUTELY ZERO WRITES.** The flash memory, bootloader, partition tables, and NVRAM configuration were untouched (0 bytes written).
- **Volatile RAM Storage (`/tmp` tmpfs):** The initial execution created 4 transient text files in volatile RAM `/tmp` (`stat_t1`, `stat_t2`, `softirqs_t1`, `softirqs_t2`) during differential CPU sampling before deleting them. In strict compliance with Architecture Directive M11.1.0.1, the script has been re-architected to use **pure in-memory stream pipelines into AWK**, eliminating temporary file creation on any filesystem.
- **Router Configuration & State:** **ZERO MODIFICATIONS.** No firewall rules were inserted, no services were stopped, no interfaces were reconfigured. All raw outputs were scrubbed through multi-layer regex filters (MACs, BSSIDs, SSIDs, WAN IP, serial numbers, credentials).

---

## 2. Empirical Ground Truth: Item-by-Item Results (R0-01 to R0-14)

### R0-01: CPU Architecture & Silicon Identity
- **Processor:** Qualcomm IPQ5018 dual-core Cortex-A53 (ARMv7 Processor rev 4 `v7l`).
- **Core Frequencies:** 2 Cores running at 1.0 GHz, BogoMIPS: 48.00.
- **CPU Features:** `half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm aes pmull sha1 sha2 crc32`.
- **Finding:** Fully confirms hardware NEON, AES, and SHA crypto extensions available for userspace BoringTun Rust.

### R0-02: Live Memory Breakdown (`/proc/meminfo`)
- **`MemTotal`:** 186,920 kB (~182.5 MB usable by Linux kernel).
- **`MemFree`:** 22,944 kB (~22.4 MB).
- **`MemAvailable`:** **10,696 kB (~10.4 MB)**.
- **`Slab`:** 60,896 kB (~59.4 MB), consisting of:
  - `SReclaimable`: 2,668 kB (~2.6 MB).
  - **`SUnreclaim`:** **58,228 kB (~56.8 MB)**.
- **Finding:** Memory pressure is high (`MemAvailable` is ~10.4 MB). `SUnreclaim` represents 56.8 MB of unevictable kernel slab caches. In accordance with Directive M11.1.0.2, this cannot be strictly equated to network DMA ring buffers without granular `/proc/slabinfo` parsing, as it encompasses general kernel slab allocations (dentries, inodes, skbuff heads, driver structures).

### R0-03: SPI NAND Partition Layout (`/proc/mtd`)
- **Total Physical Flash:** 128 MB SPI NAND (Winbond W25N01GV family).
- **Partition Verification:**
  - `mtd18`: `01e00000` (30.0 MB) "rootfs" (Slot 0, inactive).
  - `mtd19`: `01e00000` (30.0 MB) "rootfs_1" (Slot 1, **ACTIVE**).
  - `mtd20`: `03980000` (57.5 MB) "overlay" (Physical UBI container on NAND).
  - `mtd23`: `034cc000` (52.8 MB) "data" (Persistent user filesystem mounted at `/data`).

### R0-04 & R0-05: Switch Driver & MDIO Registers
- **Driver:** `yt_switch` loaded (343,529 bytes).
- **SMI Readback:** `/proc/smi` returns I/O error under standard cat (read access restricted by proprietary driver ioctl).

### R0-06: NVRAM Boot Flags
- `model`: **`CR8818`**
- `flag_boot_rootfs`: **`1`** (Confirms Slot 1 execution).
- `flag_boot_success`: **`1`**
- `flag_last_success`: **`1`**

### R0-07: Board Metadata (`ubus call system board`)
- `board_name`: `ap-mp03.3`
- `model`: `Qualcomm Technologies, Inc. IPQ5018/AP-MP03.3`
- `kernel`: `4.4.60`
- `distribution`: `OpenWrt 18.06-SNAPSHOT` (QSDK vendor release)

### R0-08: Kernel Modules Loaded
- Qualcomm NSS Subsystem: `qca_nss_drv` (826,603 B), `qca_nss_dp` (36,064 B), `qca_nss_pppoe`, `qca_nss_pptp`, `qca_nss_l2tpv2`.
- Connection Offload Engine: `ecm` (Enhanced Connection Manager), `qca_ssdk` (665,456 B).
- Wi-Fi Drivers: `umac` (2,927,364 B), `qca_ol` (1,300,691 B), `wifi_3_0`.
- Switch: `yt_switch` (Motorcomm YT9215SC driver).

### R0-09: Wi-Fi Operating Mode & Physical Link Rates
- **5 GHz Radio (`wl0` / QCN6102):**
  - Mode: `Master` (Access Point) on 5.2 GHz (Channel 40, 160 MHz bandwidth).
  - Bit Rate: **2.4019 Gb/s (2,401.9 Mbps / HE160)**.
  - Tx-Power: 24 dBm.
- **2.4 GHz Radios (`wl1` & `wl13`):**
  - Mode: `Master` on 2.412 GHz (Channel 1, 40 MHz).
  - Bit Rate: 286.8 Mb/s.
- **Finding:** Wi-Fi 6 HE160 is fully functional and running at peak 2.4 Gbps PHY link speed.

### R0-10: IP Routing & Interface Status
- `eth0` (WAN): `[REDACTED_WAN_IP]/24`, Gateway: `[REDACTED_GATEWAY_IP]` (ISP ONT).
- `br-lan` (LAN): `192.168.31.1/24`.
- `br-miot` (IoT): `192.168.32.1/24`.
- `wg0` (WireGuard): `10.99.0.1/24` with `qdisc fq_codel`.

---

## 3. Groundbreaking Discoveries from Live Baseline

### 3.1 R0-11: Process Memory Taxonomy — The RAM Reclamation Reality

```
+----------------------------------------------------------------------------------------------------+
|                                    LIVE PROCESS MEMORY PROFILING                                   |
+-------------------+-------+---------------+---------------+----------------------------------------+
| Process Name      | PID   | VmSize (Virt) | VmRSS (Phys)  | Empirical Architectural Analysis       |
+-------------------+-------+---------------+---------------+----------------------------------------+
| wg_server (Go)    | 1305  | 535,808 kB    | 20,600 kB     | WireGuard Go consumes ~20.1 MB of real |
|                   |       | (~523.2 MB)   | (~20.1 MB)    | RAM! 523 MB virtual memory arena.      |
+-------------------+-------+---------------+---------------+----------------------------------------+
| messagingagent    | 1809  | 6,836 kB      | 2,556 kB      | Xiaomi IoT MQTT cloud client.          |
|                   |       | (~6.7 MB)     | (~2.5 MB)     | Consumes only 2.5 MB RAM.              |
+-------------------+-------+---------------+---------------+----------------------------------------+
| trafficd          | 3265  | 1,696 kB      | 564 kB        | Web UI bandwidth statistics daemon.    |
|                   |       | (~1.6 MB)     | (~0.55 MB)    | Consumes only 0.55 MB RAM!             |
+-------------------+-------+---------------+---------------+----------------------------------------+
| cab_meshd         | 1382  | 2,828 kB      | 324 kB        | Xiaomi Mesh management daemon.         |
|                   |       | (~2.7 MB)     | (~0.31 MB)    | Consumes only 0.31 MB RAM!             |
+-------------------+-------+---------------+---------------+----------------------------------------+
| smartcontroller   | 3558  | 2,288 kB      | 376 kB        | Xiaomi IoT device quick-pairing daemon.|
|                   |       | (~2.2 MB)     | (~0.36 MB)    | Consumes only 0.36 MB RAM!             |
+-------------------+-------+---------------+---------------+----------------------------------------+
```

> [!IMPORTANT]
> **CRITICAL MEMORY TAKEAWAY & HYPOTHESIS FORMULATION:**
> - All 4 Xiaomi vendor daemons combined consume only **3.79 MB of physical RAM** ($2.55 + 0.55 + 0.31 + 0.36\text{ MB}$). Terminating them provides negligible memory relief while breaking the Web UI and mobile app.
> - Meanwhile, `wg_server` (WireGuard Go) alone consumes **20.1 MB of physical RAM** (`VmRSS`).
> - **Engineering Hypothesis (`TEST_HYPOTHESIS / ENGINEERING_PROJECTION`):**
>   In PC/WSL2 laboratory benchmarks, BoringTun 0.7.1 maintained a resident set size of 2.88–3.0 MB VmRSS. Under the working hypothesis that BoringTun achieves similar memory efficiency on ARMv7, projected physical RAM recovery is approximately $\sim 17.1\text{ MB}$.
>   *Constraint:* This number is strictly an engineering projection and must NOT be asserted as proven fact until BoringTun is empirically benchmarked on the physical router hardware under Step 4. Zero throughput or speed superiority is claimed prior to empirical testing.

---

### 3.2 R0-12: Time-Bounded 10-Second CPU & SoftIRQ Delta Profiling

Sampling window: $t = 10\text{ seconds}$ at live quiescent/active state.

```
--- CPU UTILIZATION (10s delta) ---
Core     Total%       User%        System%      SoftIRQ%     Idle%       
cpu0     18.56        0.80         1.80         15.97        81.44       
cpu1     3.59         0.80         2.69         0.10         96.41       

--- NET_RX SOFTIRQ (10s delta) ---
CPU0 NET_RX Delta: 12,301 events (1,230.1 events/sec)
CPU1 NET_RX Delta: 50 events (5.0 events/sec)
Current Window Distribution: CPU0 = 99.6%, CPU1 = 0.4%
```

> [!NOTE]
> **CPU BALANCE TAKEAWAY:**
> - 99.6% of software `NET_RX` softirq events hit CPU0. In accordance with Directive M11.1.0.2, these represent softirq scheduler cycles and NAPI polling invocations, not a 1:1 packet count (as NAPI processes batches of up to 64 packets per poll).
> - **However, CPU0 is currently 81.44% IDLE (Total utilization is only 18.56%)!**
> - CPU0 is NOT experiencing bottleneck or saturation under normal operation.
> - This empirically proves that **enabling RPS immediately would be a mistake**: it would introduce cross-core IPI latency and L1 cache line bouncing without relieving any actual bottleneck.
> - **RPS remains on `HOLD`** until we benchmark under heavy VPN load (Step 3/5).

---

### 3.3 R0-13: Security Listening Sockets & Firewall Preflight
- **Dropbear SSH Bindings:** `0.0.0.0:56789` (IPv4 all interfaces) and `:::56789` (IPv6 all interfaces).
- **WireGuard:** Listening on UDP 51820.
- **dnsmasq:** Listening on port 53 across local IP addresses.
- **Firewall Nuance & Dual-Stack Preflight:**
  * While Dropbear is bound to `0.0.0.0` and `:::`, socket binding alone does NOT prove direct Internet reachability. The WAN interface holds private IP `[REDACTED_WAN_IP]` behind an upstream ONT. Reachability from the public Internet requires upstream ONT port-forwarding/DMZ and permissive netfilter firewall chains (`iptables` and `ip6tables`).
  * In OpenWrt fw3, incoming WAN packets traverse `INPUT -> delegate_input -> zone_wan_input`.
  * **Crucial Dual-Stack Finding:** An `iptables` rule dropping port 56789 on `zone_wan_input` only affects **IPv4** traffic. It does NOT protect against **IPv6** connections arriving at `:::56789`! Both `iptables` AND `ip6tables` must be configured symmetrically.

---

### 3.4 R0-14: Qualcomm NSS Hardware Offload Statistics
- Common IPv4 RX: 98,237,131 packets / 98.8 GB.
- Special IPv4 RX (Rule Match): 95,251,332 packets / 96.9 GB.
- Hash Hits: 95,311,622 (Lookups during forward, create, and destroy).
- Drops: **0 drops across all 4 RX queues and rule tables**.
- **Internal Rule Match Ratio:**
  $$\text{Internal NSS Rule Match Ratio} = \frac{95,251,332}{98,237,131} \times 100\% = \mathbf{96.96\%}$$
- **Nuanced Interpretation:**
  This 96.96% ratio reflects the internal rule match rate of IPv4 packets delivered to the NSS engine. It must NOT be interpreted as an absolute global offload percentage of 100% of all router transit traffic, because non-NSS interfaces (such as `wg0` and local proxies) are handled by the host CPU.

---

## 4. Reconciled Roadmap for Next Action Steps

Based on the confirmed R0 telemetry, the 6-step roadmap is aligned:

```
+--------+------------------------------------+------------+---------------------------------------------+
| Thứ Tự | Hạng Mục Công Việc                 | Phê Duyệt  | Căn Cứ Thực Nghiệm Vừa Đo Đạc               |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 1 | M11.1 R0 Live Baseline Audit       | HOÀN THÀNH | Đã đo đạc đủ 14 hạng mục R0 thực tế         |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 2 | Chặn WAN SSH port 56789            | PREFLIGHT  | Xác nhận 0.0.0.0 & ::: mở Dropbear;         |
|        | (Dual-stack IPv4/IPv6 + Watchdog)  | CHỜ DUYỆT  | Cần chặn cả iptables & ip6tables            |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 3 | Đo CPU0/CPU1 khi tải VPN iperf3    | CHỜ DUYỆT  | Baseline tĩnh là 18.5% CPU0; cần đo         |
|        |                                    |            | khi có lưu lượng VPN thực tế                |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 4 | Chạy BoringTun Rust trên wg1:51821 | CHỜ DUYỆT  | Go đang chiếm 20.1 MB RAM; BoringTun sẽ     |
|        | (Sandbox độc lập, giữ nguyên wg0)  |            | kiểm chứng giả thuyết tiết kiệm ~17 MB      |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 5 | Thử RPS nếu CPU0 tải VPN > 80%     | GIỮ NGUYÊN | Chỉ thử nếu Bước 3 chứng minh CPU0 quá tải  |
+--------+------------------------------------+------------+---------------------------------------------+
| Bước 6 | Benchmark DNS và tinh chỉnh Wi-Fi  | GIỮ NGUYÊN | dnsmasq cache-size=2048; Wi-Fi HE160 giữ    |
|        |                                    |            | nguyên 2.4 Gbps                             |
+--------+------------------------------------+------------+---------------------------------------------+
```

---

## 5. Kết luận & Cổng kiểm soát an toàn (Gate M11.1.0.1)

Số liệu R0 Baseline đã được hiệu chỉnh chính xác theo Architecture Directive M11.1.0.1:
1. Đã phân định rõ ranh giới lưu trữ: 0 bytes ghi vào NAND/flash, script được tái cấu trúc thành pure in-memory stream pipeline.
2. Đã làm sạch toàn bộ dữ liệu nhạy cảm (SSID, BSSID/MAC, serial, WAN IP, credentials).
3. Đã xác lập giả thuyết tiết kiệm RAM của BoringTun Rust (`TEST_HYPOTHESIS`), không khẳng định thành sự thật trước khi đo đạc.
4. Đã hoàn thiện bộ test harness kiểm thử watchdog SIGHUP và dual-stack trên PC.

*(Tuân thủ tuyệt đối quy tắc `AGENTS.md`: Tạm dừng tại đây, không SSH vào router, không thay đổi firewall và chờ chỉ thị từ Architecture Lead).*
