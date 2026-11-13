# M12.7 Live Optimization, Hardening & Hardware Verification Report (CR8808 / RA82 v1.4.31)

- **Date:** 2026-11-13
- **Target Hardware:** Xiaomi CR8808 Ver.B (`IPQ5018`, Dual-Core ARMv7, ROM `RA82 v1.4.31`, Linux `4.4.60`) & Upstream FPT `AX3000CV2` ONT (`192.168.100.1`)
- **Mode:** Live non-destructive execution (zero router reboot, zero NAND firmware flash, production `wg0` preserved)

---

## 1. Upstream FPT ONT (`192.168.100.1`) Remote Access Fixes

| Setting | Before | After (Verified via `ubus`) |
| :--- | :--- | :--- |
| DHCP Static Reservation (`dhcp_reservation_get`) | `host: []` (dynamic lease) | `_idx: cfg04fe63` — `192.168.100.75` bound to router WAN MAC |
| Port Forwarding (`portfwd_get`) | `redirect: []` (empty) | `_idx: cfg333837` — `WireGuard_51820` (`UDP 51820 -> 192.168.100.75:51820`, `enabled: true`) |
| DMZ (`dmz_get`) | `enabled: true`, `192.168.100.75` | `enabled: true`, `192.168.100.75` |

Desktop WireGuard client profiles (`home-full.conf`, `home-gaming.conf`, `home-split.conf`) were also fixed:
- Updated `MTU` from `1420` -> `1380` (PPPoE `1492`-safe).
- Removed `::/0` IPv6 blackhole from `home-full.conf` (`AllowedIPs = 0.0.0.0/0`).
- Switched `DNS` in `home-full.conf` and `home-gaming.conf` to `10.99.0.1` so remote VPN clients benefit from router AdBlock, Smart Game DNS Steering, and Zapret.

---

## 2. Router Live Fixes, Multi-Core Optimization & Security Hardening

### 2.1 Eliminated 5-Minute DNS/TLS Reset Loop (`/data/zapret/run.sh`)
- **Root Cause Fixed:** Cron (`*/5 * * * *`) previously forced `/etc/init.d/dnsmasq restart` and `killall -9 tpws` unconditionally every 5 minutes, clearing the DNS cache and resetting active TLS connections. `/data/dns_game.conf` was also not loaded in `/tmp/dnsmasq.d/`.
- **Changes Applied:**
  - Replaced unconditional restarts with `cmp -s` config-diff checks and `pidof` guards.
  - Enabled `/tmp/dnsmasq.d/dns_game.conf` (`1633 B`) and `/tmp/dnsmasq.d/perf_opt.conf` (`cache-size=4096`, `min-cache-ttl=300`, `neg-ttl=60`).
  - Verified `dnsmasq --test` (`syntax check OK.`) and ran `/data/zapret/run.sh` twice consecutively: `dnsmasq` (`PID 3210`) and `tpws` (`PID 2424`) remained uninterrupted on the second run.
  - Functional DNS check: `nslookup doubleclick.net 127.0.0.1` blocked (`can't resolve`), `nslookup google.com 127.0.0.1` resolved cleanly.

### 2.2 Multi-Core RPS/XPS, IRQ Affinity, Sysctl & Firewall Persistence (`/data/tune_network.sh`, `/data/auto_ssh.sh`, `/etc/crontabs/root`)
- **Multi-Core Steering & IRQ Affinity:**
  - `net.core.rps_sock_flow_entries = 32768`
  - `eth0`, `eth1`, `wl0`, `wl1`: `rps_cpus = 2`, `rps_flow_cnt = 4096`, `xps_cpus = 2`
  - `br-lan`, `wg0`: `rps_cpus = 3`, `rps_flow_cnt = 4096`
  - IRQs: `IRQ 28` (`nss_queue0`) = `1`; `IRQ 29, 69, 78, 91, 92, 98` = `2`.
  - Verified NSS offload active: `dev.nss.general.redirect = 1`, `dev.nss.rps.enable = 1`.
- **Kernel Networking, Conntrack & VM Tuning:**
  - `net.core.netdev_max_backlog = 16384`, `net.core.netdev_budget = 600`
  - `net.core.rmem_max = 4194304`, `wmem_max = 4194304`, `tcp_fastopen = 3`, `tcp_low_latency = 1`, `tcp_slow_start_after_idle = 0`, `tcp_autocorking = 0`, `tcp_mtu_probing = 1`
  - `net.netfilter.nf_conntrack_max = 32768`, `nf_conntrack_tcp_timeout_established = 7200`
  - `vm.min_free_kbytes = 4096`, `vm.vfs_cache_pressure = 150`, `vm.swappiness = 10`
- **Persistence & Security Hardening:**
  - Persisted Dropbear host key (`SHA256:3zcodt2sIQAOwD0Uc8cbFDTJuKWStQMoZKXIKl/rAaU`) to `/data/etc/dropbear_rsa_host_key` and updated `/data/auto_ssh.sh` to restore it on boot (`firewall.auto_ssh.reload = '1'`).
  - Added idempotent `wg0` firewall rules (`INPUT udp/51820`, `FORWARD -i wg0/-o wg0`, `POSTROUTING MASQUERADE`, `TCPMSS`) to `/data/tune_network.sh`.
  - Added `ip6tables` WAN (`eth0`) `INPUT` and `FORWARD` `DROP` rules allowing only `RELATED,ESTABLISHED`, `ipv6-icmp`, DHCPv6 (`udp 546`), and WireGuard (`udp 51820`).
  - Removed unused `/data/dnsproxy` (`11.4 MB`), reclaiming `/data` space (`10.7M / 24%` -> `4.9M / 11%` used even with `/data/bin/{iperf3,boringtun-cli}` installed; `39.7M` free).
  - Disabled `/usr/sbin/otapredownload` in cron and scheduled `/data/tune_network.sh` every 5 minutes.

---

## 3. Live Hardware Benchmarks (Before vs After on CR8808)

### 3.1 Multi-Core SoftIRQ Balancing (`/proc/softirqs` & `/proc/stat`)

| Metric | Baseline (Before RPS/XPS) | Live Gigabit Load (After RPS/XPS) |
| :--- | :--- | :--- |
| `NET_RX` CPU0 vs CPU1 Share | `99.56%` CPU0 / `0.44%` CPU1 (3s delta: `96.1%` / `3.9%`) | **`+43,981` CPU0 (`62.2%`) / `+26,767` CPU1 (`37.8%`)** |
| `TASKLET` CPU0 vs CPU1 Share | `100.0%` CPU0 / `0.0%` CPU1 | **`+344` CPU0 (`55.8%`) / `+273` CPU1 (`44.2%`)** |
| SoftIRQ CPU Jiffies (`/proc/stat`) | `97.8%` CPU0 / `2.2%` CPU1 | **`+370` CPU0 (`62.8%`) / `+219` CPU1 (`37.2%`)** |

### 3.2 `iperf3` LAN <-> Router Gigabit Throughput (`-P 4`, 5s)
- **Upload (`Workstation -> 192.168.31.1:5201`):** **`972 Mbits/sec` sender / `939 Mbits/sec` receiver** (`575 MBytes`, `0` retransmits).
- **Download (`192.168.31.1:5201 -> Workstation -R`):** **`940 Mbits/sec` sender / `951 Mbits/sec` receiver** (`567 MBytes`).

### 3.3 Post-Benchmark Health, NSS Offload & Wi-Fi 6 HE160
- **NSS / ECM Offload (`/sys/kernel/debug/ecm`):** `94 / 98` active flows accelerated (`95.9%`: `68` TCP, `26` UDP), `driver_fail_limit_default = 250`, `nack_limit_default = 250`.
- **Wi-Fi 5 GHz (`wl0`):** `channel 40 (5200 MHz), width: 160 MHz, center1: 5250 MHz, txpower 24.00 dBm`.
- **Thermals & RAM:** `68–69°C` across `thermal_zone0..3`; `MemAvailable = 24,244 kB`.

### 3.4 BoringTun Rust (`wg1`) Hardware Qualification vs Go `wg_server` (`wg0`)
Tested via `deploy_wg1.sh` + `/data/bin/boringtun-cli` on isolated `wg1` (`10.99.1.1/24`, `UDP 51821`) and torn down cleanly via `teardown_wg1.sh`:

| Metric | Production `wg_server` (`wg0`, Go) | Qualified `boringtun-cli` (`wg1`, Rust) |
| :--- | :--- | :--- |
| `VmSize` | `535,296 kB` (`522 MB`) | **`5,492 kB` (`5.36 MB`, ~97x smaller)** |
| `VmRSS` | `3,448 kB` (`3.37 MB`) | **`1,032 kB` (`1.01 MB`, ~3.3x smaller)** |
| Threads | `10` | **`3`** |
| Production `wg0` Status | `PID 1341`, `UP`, `UDP 51820` | 100% untouched during & after teardown |
