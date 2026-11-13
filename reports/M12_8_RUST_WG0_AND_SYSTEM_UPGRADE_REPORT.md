# M12.8 Live System Upgrade Report: Rust `boringtun-cli` `wg0`, Memory & Syslog Hardening, Offloads, Low-Latency `fq_codel`, and Telemetry v2

**Target Hardware:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Dual-Core IPQ50xx + Qualcomm NSS NPU, Linux `4.4.60` armv7l)  
**Branch:** `feature/m12-ra82-performance-modernization`  
**Status:** Applied Live & Verified on `192.168.31.1` (Zero Reboots, Zero NAND Flashes)

---

## 1. Executive Summary

Building on M12.7's network, DNS, and firewall foundation, **M12.8** executed a live software, kernel queue, offload, and telemetry upgrade on the Xiaomi RA82 router:

1. **Production WireGuard `wg0` Upgraded from Go to Rust (`boringtun-cli` + `wireguard-tools`):** Replaced the `3.2 MB` Go `/data/wg_server` daemon (`535,296 kB` VSZ / `3,588 kB` RSS) with statically linked ARMv7 Rust `/data/bin/boringtun-cli` (`5,512 kB` VSZ / `1,236 kB` RSS) controlled via `/data/bin/wg` (`v1.0.20260223`). Verified end-to-end with a real Noise_IKpsk2 handshake and 5/5 ICMP echo replies over an encrypted tunnel (`0.997 ms` min / `2.670 ms` avg RTT).
2. **Memory Reclamation & Syslog Churn Elimination:** Disabled `dnsmasq` `logqueries='1'` (`log-queries=extra`) and stopped/disabled Xiaomi bloat daemons (`messagingagent.sh`, `smartcontroller`), raising `MemFree` from `27,960 kB` to `33,732 kB` (`+5,772 kB`) and `MemAvailable` from `24,036 kB` to `27,668 kB` (`+3,632 kB`).
3. **Hardware Offloads, Low-Latency `fq_codel`, & `802.11k/v` Roaming:** Enabled `eth0` Generic Segmentation Offload (`gso: off [requested on]` -> `on`) and `wl0` `tx-checksumming: on`, tuned `fq_codel` on `wifi0`/`wifi1`/`wg0` (`limit 2048p quantum 300 target 3.0ms interval 60.0ms ecn`), and enabled `802.11k` (`rrm 1`) and `802.11v` (`wnm 1`) on `wl0`.
4. **Upgraded Rust `stats_collector` v2 & Restored Telemetry Daemons:** Compiled and deployed a statically linked ARMv7 Rust v2 telemetry daemon (`471 KB`, `656 kB` VSZ in `--daemon` mode) with real `df -k /data`, live Zapret & AdBlock counts, `wl0` + `wl1` + wired `br-lan` + `wg0` client detection, and restored `/data/fpt_daemon.sh` + `/data/flight_recorder.sh` in `/data/auto_ssh.sh`.

---

## 2. Before vs. After Verified Metrics

| Metric / Component | Before M12.8 | After M12.8 | Verified Delta / Outcome |
| --- | --- | --- | --- |
| `MemFree` (`/proc/meminfo`) | `27,960 kB` | `33,732 kB` | **`+5,772 kB`** |
| `MemAvailable` (`/proc/meminfo`) | `24,036 kB` | `27,668 kB` | **`+3,632 kB`** |
| `/data` UBIFS Flash Usage | `5,100 KB` (`11%`, `40,572 KB` free) | `3,084 KB` (`7%`, `42,588 KB` free) | **`-2,016 KB` used** (deleted `3.2 MB` Go `wg_server`) |
| `dnsmasq` `logqueries` | `1` (`log-queries=extra` active) | `0` (`log_queries_conf=0`) | Syslog query spam eliminated; `syntax check OK.` |
| `messagingagent.sh` & `smartcontroller` | Running (`4,032` + `1,096 kB` RSS) | Stopped & `rc.d` disabled | Persistence suppressed via `/data/tune_network.sh` |
| `eth0` `generic-segmentation-offload` | `off [requested on]` | `on` | Enabled via `ethtool -K eth0 gso on ...` |
| `wl0` `tx-checksumming` | `off` | `on` | Enabled via `ethtool -K wl0 tx on ...` |
| `fq_codel` (`wifi0`, `wifi1`, `wg0`) | `0:` default (`1024p`, `quantum 1514/1420`, `5ms/100ms`) | `8001:`/`8002:`/`8003:` (`limit 2048p`, `quantum 300`, `3.0ms/60.0ms`, `ecn`) | Active low-latency AQM on wireless & VPN interfaces |
| `wl0` `802.11k` / `802.11v` | `rrm=0`, `wnm=0` | `get_rrm:1`, `get_wnm:1` (`rc=0`) | Assisted roaming active & persisted in `/data/tune_network.sh` |
| `wg0` Daemon Engine | Go `/data/wg_server` (`535,296 kB` VSZ, `3,588 kB` RSS) | Rust `/data/bin/boringtun-cli` (`5,512 kB` VSZ, `1,236 kB` RSS) | **`-99%` VSZ**, **`-2,352 kB` RSS**, encrypted `5/5` ping pass |
| Dashboard Collectors | `fpt_daemon.sh` & `flight_recorder.sh` down; hardcoded `stats_collector` | All 3 collectors running (`1625`, `1632`, `1633`); dynamic v2 JSON | Real `disk`, `zapret` (`43`/`10`), `adblock` (`18461`), `wireguard`, wired & VPN peers |

---

## 3. Implementation Details & Verification Evidence

### 3.1 DNS Logging Churn & Bloat Suppression
- Executed:
  - `uci set dhcp.@dnsmasq[0].logqueries='0' && uci commit dhcp && /etc/init.d/dnsmasq restart`
  - `/etc/init.d/messagingagent.sh disable` and `/etc/init.d/smartcontroller disable`, verified `/etc/rc.d/*messaging*` / `/etc/rc.d/*smart*` absent (`rc_d_disabled_clean`).
- Added `killall -q messagingagent smartcontroller 2>/dev/null || true` inside `/data/tune_network.sh` (backed up to `/data/tune_network.sh.bak.m128`).

### 3.2 Offloads, Low-Latency `fq_codel`, and `802.11k/v`
Appended an idempotent `# M12.8` tuning block to `/data/tune_network.sh`:
- `ethtool -K eth0 gso on gro on tso on sg on`, `ethtool -K eth1 gso on gro on tso on sg on`
- `ethtool -K wl0 tx on sg on gso on gro on`, `ethtool -K wl1 tx on sg on gso on gro on`
- `tc qdisc replace dev "$dev" root fq_codel limit 2048 flows 1024 quantum 300 target 3ms interval 60ms ecn` across `wifi0`, `wifi1`, `wg0`
- `iwpriv wl0 rrm 1` and `iwpriv wl0 wnm 1`

### 3.3 Production `wg0` Upgrade to Rust `boringtun-cli` + Real Tunnel Verification
- Deployed `wireguard-tools v1.0.20260223` (`/data/bin/wg`, `127.5K`).
- Migrated the existing server private key directly on-router into `/data/etc/wg0_server.key` (`chmod 600`, `45 B`) without exposing key material.
- Replaced `/data/start_wireguard.sh` (backup: `/data/start_wireguard.sh.bak.m128`) to launch `/data/bin/boringtun-cli --disable-drop-privileges --foreground --threads 2 wg0`, bring up `10.99.0.1/24` (`mtu 1420 txqueuelen 2000`), configure peer & `listen-port 51820` via `/data/bin/wg set`, set `oom_score_adj=-1000`, and re-apply `/data/tune_network.sh`.
- Updated `/data/auto_ssh.sh` (backup: `/data/auto_ssh.sh.bak.m128`) watchdog from `pidof wg_server` to `pidof boringtun-cli`.
- **Live End-to-End Tunnel Verification (WSL2 `wgtest` -> `192.168.31.1:51820`):**
  - `ping -I wgtest -c 5 -W 2 10.99.0.1` -> `5 packets transmitted, 5 received, 0% packet loss`, `rtt min/avg/max/mdev = 0.997/2.670/8.929/3.130 ms`.
  - Client `wg show wgtest`: `latest handshake: 4 seconds ago`, `transfer: 672 B received, 788 B sent`.
  - Router `/data/bin/wg show wg0`: `listening port: 51820`, peer endpoint observed (`192.168.31.106:55075`), `transfer: 420 B received, 420 B sent` (Note: BoringTun's UAPI reports `last_handshake_time_sec` using monotonic ticks, causing `wireguard-tools` to print a shifted relative age even after a fresh handshake).
  - Removed ephemeral `wgtest` interface and deleted obsolete `/data/wg_server` (`3.2M`).

### 3.4 Rust `stats_collector` v2 (`src/stats_collector/stats_collector.rs`) & Collector Daemons
- Authored standalone Rust source in `src/stats_collector/stats_collector.rs` and cross-compiled with `rustc 1.99.1`:
  - `rustc --target armv7-unknown-linux-musleabihf -C linker=arm-linux-gnueabihf-gcc -C opt-level=z -C strip=symbols` -> `471 KB` statically linked, stripped ARMv7 ELF.
- Eliminated hardcoded mock metrics and hardcoded device identifiers:
  - Uses `df -k /data` (`48168` total, `3084` used, `42588` available, `7%`), `/data/zapret/hosts.txt` (`43` active domain rules), `ipset list zapret_unblock` (`10` resolved IPs), `/tmp/dnsmasq.d/adblock.conf` (`18461` block rules), `/data/bin/wg show wg0 dump`, `/etc/config/wireless`, `wlanconfig wl0` + `wl1`, `/proc/net/arp` (detecting wired Gigabit clients on `br-lan` such as `192.168.31.106` and MIoT on `br-miot`), and `/tmp/dhcp.leases`.
- Restored `/data/fpt_daemon.sh` and `/data/flight_recorder.sh` and registered both in `/data/auto_ssh.sh` (`</dev/null >/dev/null 2>&1 &`).
- Verified `http://127.0.0.1:8888/cgi-bin/stats` returns valid JSON (`nss.fastpath_pct: 96.6`, `fastpath_byte_pct: 98.6`, `services.wireguard.running: true`, `clients` includes 5GHz, IoT, Wired 1000Mbps, and WireGuard peer), `/tmp/flight_recorder.log` actively logs (`LAN 1.205 ms • WAN 29.905 ms • NPU: 4%`), and `/tmp/fpt_cache.json` populates live FPT ONT telemetry.

### 3.5 Security Scan Note
- Attempted `snyk_code_scan` on `src/stats_collector` per workspace security rule; the Snyk MCP server returned `User not authenticated. Please run 'snyk_auth' first`. No unauthenticated bypass was attempted; local SAST remains pending Snyk authentication.
