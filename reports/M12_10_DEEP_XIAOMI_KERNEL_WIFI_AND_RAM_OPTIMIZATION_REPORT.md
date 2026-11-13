# M12.10 Live System Optimization Report: Firmware `logrotate` UID Bug Fix (`-10 MB` `Shmem`), `eth0`/`eth1` `mq` `fq_codel`, Copy-Engine IRQ Split, QCA Wi-Fi 6 `ANI`, Kernel TCP Stack & Timezone Fix

**Target Hardware:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Dual-Core IPQ50xx + Qualcomm NSS NPU, Linux `4.4.60` armv7l)  
**Branch:** `feature/m12-ra82-performance-modernization`  
**Status:** Applied Live & Verified on `192.168.31.1` (Zero Reboots, Zero NAND Flashes)

---

## 1. Executive Summary

Going beyond WireGuard and dashboard work into the core Xiaomi firmware, **M12.10** audited kernel interrupts, `qdisc` queues, Qualcomm Wi-Fi DSP flags, TCP stack parameters, timezone configuration, and `tmpfs` memory leaks:

1. **Fixed Stock RA82 `logrotate` UID `1000` Ownership Bug (`+9.1 MB` `MemAvailable`):** Discovered that SquashFS `/etc/logrotate.conf` and `/etc/logrotate.d/*` were owned by UID `1000`, causing `logrotate` to silently skip every 2 minutes (`Ignoring /etc/logrotate.conf because the file owner is wrong ... Handling 0 logs`). As a result, `/tmp/messages` (`6.0 MB`) and `/tmp/wifi_analysis.log` (`4.0 MB`) leaked continuously in `tmpfs`. Deploying `0:0`-owned configs under `/data/etc/logrotate.conf` and rotating in RAM (`/tmp/log`) cut `Shmem` from `13,068 kB` to `2,904 kB` (`-10,164 kB`), lifting **`MemAvailable` from `24,280 kB` to `33,352 kB` (`+9,072 kB`)**.
2. **Deep `eth0` / `eth1` Multi-Queue `fq_codel` & Copy-Engine SMP IRQ Balancing:** Tuned all 4 hardware `mq` sub-queues (`eth0` `:1`/`:2` and `eth1` `:1`/`:2`) to low-latency `fq_codel` (`limit 2048p flows 1024 quantum 1514 target 2.0ms interval 40.0ms ecn`) and split high-volume interrupts across both CPU cores (`irq 25` & `40` -> CPU0, `irq 26` & `41` -> CPU1).
3. **Qualcomm QCA Wi-Fi 6 DSP `ANI` + Full Dual-Band `802.11k/v`:** Enabled hardware Adaptive Noise Immunity (`ani_enable=1`) on both 5GHz (`wifi1`) and 2.4GHz (`wifi0`) radios, and enabled `802.11k`/`802.11v` (`rrm 1`, `wnm 1`) on `wl1` (`2.4GHz`) to match `wl0` (`5GHz`).
4. **Kernel TCP, Socket Backlog, & Neighbour Table Tuning + Timezone Fix (`ICT-7`):** Applied low-latency TCP/socket/ARP sysctls (`tcp_ecn=2`, `tcp_tw_reuse=1`, `tcp_fin_timeout=15`, `somaxconn=4096`, `ip_local_port_range=10240 65535`, `gc_thresh3=2048`) and fixed router timezone from `+11` (`<+1030>-10:30<+11>-11`) to Vietnam local time (`ICT-7`).

---

## 2. Before vs. After Verified Metrics

| Parameter / Resource | Before M12.10 | After M12.10 | Verified Delta / Result |
| --- | --- | --- | --- |
| `MemFree` (`/proc/meminfo`) | `24,544 kB` | `32,892 kB` | **`+8,348 kB`** |
| `MemAvailable` (`/proc/meminfo`) | `24,280 kB` | `33,352 kB` | **`+9,072 kB`** |
| `Shmem` (`tmpfs` locked RAM) | `13,068 kB` | `2,904 kB` | **`-10,164 kB` released** |
| `/tmp` (`tmpfs`) Used | `13,016 KB` (`14%`) | `2,852 KB` (`3%`) | **`-10,164 KB` freed** (`/tmp/messages` `6.0M`->`33.4K`, `/tmp/wifi_analysis.log` `4.0M`->`39.5K`) |
| `logrotate -d` Execution | Skipped (`UID 1000`, `Handling 0 logs`) | `Handling 2 logs` (`0:0`, `chmod 600`) | Active 2-min cron rotation in RAM (`/tmp/log`) |
| `eth0` & `eth1` `mq` `fq_codel` | Default `0:` (`1024p`, `5.0ms/100.0ms`) | Handles `8004:`–`8007:` (`2048p`, `2.0ms/40.0ms`, `ecn`) | Active low-latency queue discipline on WAN & LAN switch ports |
| NSS & QCA Copy-Engine IRQs | `irq26=3`, `irq40=3`, `irq41=3` (`ce2` `4.11M` / `ce1` `2.08M` mostly on CPU0) | `irq25=1`, `irq26=2`, `irq40=1`, `irq41=2` | Dedicated CPU0/CPU1 split |
| QCA Radio `ANI` (`wifi1`, `wifi0`) | `get_ani_enable:0` | **`get_ani_enable:1`** on both radios | Hardware interference immunity active |
| `wl1` (`2.4GHz`) `802.11k/v` | `get_rrm:0`, `get_wnm:0` | **`get_rrm:1`, `get_wnm:1`** | Matches `wl0` (`5GHz`) roaming support |
| Kernel TCP & Socket Sysctls | `ecn=0`, `tw_reuse=0`, `fin=30`, `somaxconn=128`, `optmem=10240`, `gc_thresh3=1024` | `ecn=2`, `tw_reuse=1`, `fin=15`, `somaxconn=4096`, `optmem=65536`, `gc_thresh3=2048`, `port_range=10240 65535` | Applied & persisted in `/data/tune_network.sh` |
| Router Timezone (`date`) | `Sat Nov 14 03:49:54 +11 2026` | **`Fri Nov 13 23:49:55 ICT 2026`** | UCI `ICT-7`; `flight_recorder.log` timestamps synced (`[23:49:55]`) |
| `/data` UBIFS Flash Usage | `3,076 KB` (`7%`, `42,600 KB` free) | `3,080 KB` (`7%`, `42,592 KB` free) | Only `+4 KB` for persistent `logrotate` configs |

---

## 3. Implementation Details & Verification

### 3.1 Root Cause & Fix for SquashFS `logrotate` Bug
- `logrotate -d /etc/logrotate.conf` revealed the stock RA82 SquashFS image ships `/etc/logrotate.conf` owned by UID `1000`, causing `logrotate` (invoked every 2 minutes by `/etc/crontabs/root`) to abort without rotating anything.
- Created root-owned (`0:0`, `chmod 600` files / `chmod 700` dir) configuration at `/data/etc/logrotate.conf` and `/data/etc/logrotate.d/{messages,wifi_analysis}` with `size 256k` / `size 128k`, `olddir /tmp/log`, `copytruncate`, `compress`, and `rotate 1` so rotated archives remain in `tmpfs` without adding UBIFS/NAND erase cycles.
- Updated `/etc/crontabs/root` to invoke `logrotate /data/etc/logrotate.conf`, truncated both active logs in-place (`cat "${f}.tmp" > "$f"`) preserving `syslog-ng` open file descriptors, cleared `/data/usr/log/*`, and added a size-guard in `/data/tune_network.sh`.

### 3.2 Deep Kernel, Offload, Wi-Fi DSP & IRQ Persistence (`/data/tune_network.sh`)
- Appended `# M12.10` section to `/data/tune_network.sh` (`sh -n` validated and executed live):
  - Copy-Engine & NSS empty-buffer SMP IRQ affinity (`25=1`, `26=2`, `40=1`, `41=2`).
  - `tc qdisc replace dev "$dev" parent :"$q" fq_codel limit 2048 flows 1024 quantum 1514 target 2ms interval 40ms ecn` for `eth0` and `eth1` (`q` in `1 2`), confirmed as handles `8004:`/`8005:` on `eth0` and `8006:`/`8007:` on `eth1`.
  - TCP, keepalive, `somaxconn`, `optmem_max`, ephemeral ports, and neighbour cache sysctls.
  - `iwpriv wifi1 ani_enable 1`, `iwpriv wifi0 ani_enable 1`, `iwpriv wl1 rrm 1`, and `iwpriv wl1 wnm 1`.
  - Persistent `/tmp/TZ` (`ICT-7`), `chown 0:0` on `/data/etc/logrotate*`, and `512 KB` emergency cap on `/tmp/messages` and `/tmp/wifi_analysis.log`.

### 3.3 Post-Tuning Live Health Verification
- `curl -s http://127.0.0.1:8888/cgi-bin/stats` verified valid JSON with Qualcomm NSS active (`npu_avg: 4%`, `fastpath_pct: 96.0%`, `fastpath_byte_pct: 98.6%`, `fp_packets: 40,734,930`), WireGuard `boringtun-cli` up (`14.2 MB` RX / `211.6 MB` TX), and `flight_recorder.log` reporting `[23:49:55] LAN 1.267 ms • WAN 30.031 ms • NPU: 4%`.
