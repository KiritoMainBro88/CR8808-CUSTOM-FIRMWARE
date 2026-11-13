# M12.9 Live System Upgrade Report: `procd` Bloat Elimination, WAN DNS/SSH Hardening, DuckDNS & `wg0` Self-Healing, and Dashboard v2.1

**Target Hardware:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Dual-Core IPQ50xx + Qualcomm NSS NPU, Linux `4.4.60` armv7l)  
**Branch:** `feature/m12-ra82-performance-modernization`  
**Status:** Applied Live & Verified on `192.168.31.1` (Zero Reboots, Zero NAND Flashes)

---

## 1. Executive Summary

Following the owner's real mobile 5G WireGuard test (`wg show wg0` verified `14.22 MiB` received / `211.57 MiB` sent on Rust `boringtun-cli` PID `2703` with `1,388 kB` RSS), **M12.9** eliminated remaining background `procd`/cron bloat, locked down WAN-facing DNS and SSH attack surfaces, added automatic `wg0` self-healing and DuckDNS log rotation, and upgraded both the Rust telemetry collector (`v2.1`) and Web Dashboard with live WireGuard VPN controls.

---

## 2. Before vs. After Verified Metrics

| Optimization Area | Before M12.9 | After M12.9 | Verified Outcome |
| --- | --- | --- | --- |
| `messagingagent.sh` (`procd` respawn) | Respawned via `procd` (`5,572 kB` RSS, PID `1423`) | Stopped & unregistered (`ubus` service `{}`) | `pids_messaging_smart=none` verified after 5s |
| Xiaomi telemetry cron jobs | `sp_check.sh` (`*/5`) & `mobile_accel.sh` (`*/3`) active | Commented out in `/etc/crontabs/root`; `/tmp/stat_points` removed | Zero periodic Xiaomi cloud stat-point uploads |
| `MemFree` / `MemAvailable` | `28,812 kB` / `24,948 kB` | `31,068 kB` / `27,232 kB` | **`+2,256 kB`** MemFree / **`+2,284 kB`** MemAvailable; dashboard RAM usage `59%` -> `58%` |
| `dnsmasq` WAN `:53` Exposure | Bound on WAN IP `192.168.100.75:53` (TCP & UDP) | `except-interface=eth0` persisted in `/data/zapret/run.sh` | WAN IP `:53` closed; `127.0.0.1`, `192.168.31.1`, `192.168.32.1`, `10.99.0.1` `:53` active; `syntax check OK.` |
| WAN SSH `tcp/56789` Hardening | Unthrottled `ACCEPT` in `zone_wan_input` | `input_wan_rule` allows upstream subnet + `--syn` limit (`6/min`, burst `10`) -> `DROP` | Anti-brute-force protection active in `iptables` |
| WireGuard `wg0` Watchdog | Checked only via SSH login (`auto_ssh.sh`) | Checked every 5 min in `/data/tune_network.sh` (`pidof boringtun-cli` + `10.99.0.1`) | Self-healing tunnel recovery + `fq_codel` `8001:`/`8002:`/`8003:` intact |
| DuckDNS Script & `/tmp/duckdns.log` | `549` unbounded lines, no HTTP timeout | `curl -m 10` timeout + 50-line log cap | Verified `50 /tmp/duckdns.log` (`DuckDNS update: OK`) |
| `/data` Cleanliness & Flash | Obsolete `.bak` / `.old.sh` scripts (`3,188 KB` after M12.8 cleanup) | Removed 6 obsolete backup files; synced `/data/auto_run.sh` | **`3,076 KB` used (`7%`, `42,600 KB` free)** |
| Dashboard & `stats_collector` (`v2.1`) | `v2` basic WG string; no WireGuard UI card | `v2.1` (`475 KB` ARMv7 ELF) + `test_wg` CGI action + `#wgStatusBadge` UI card | Live 5G VPN metrics (`14.2 MB` RX / `211.6 MB` TX), `Wired GbE`, & `VPN Tunnel` badges |

---

## 3. Implementation & Verification Details

### 3.1 `procd` Service & Telemetry Cron Cleanup
- Executed `/etc/init.d/messagingagent.sh stop && /etc/init.d/messagingagent.sh disable` and `/etc/init.d/smartcontroller stop && /etc/init.d/smartcontroller disable`. Verified `ubus call service list '{"name":"messagingagent.sh"}'` returned `{}` and no `messagingagent` or `smartcontroller` processes respawned after 5 seconds.
- Commented out `sp_check.sh` and `mobile_accel.sh` in `/etc/crontabs/root`, removed `/tmp/stat_points`, and reloaded `cron`.

### 3.2 WAN Surface Hardening, `wg0` Watchdog & Script Hygiene
- Restored clean `/data/tune_network.sh` lines from backup prior to applying clean `# M12.8` (`procd`-safe service stops, `ethtool -K`, `tc qdisc replace fq_codel`, `802.11k/v`) and `# M12.9` blocks:
  - Added WAN SSH rate limiting rules in `input_wan_rule` (`--syn -m limit --limit 6/min --limit-burst 10 -j ACCEPT` followed by `--syn -j DROP`, with explicit allow for upstream `192.168.100.0/24`).
  - Added self-healing `wg0` watchdog (`if ! pidof boringtun-cli >/dev/null || ! ip addr show dev wg0 2>/dev/null | grep -q '10.99.0.1'`).
- Updated `/data/zapret/run.sh` to inject `except-interface=eth0` into `/tmp/perf_opt.conf.tmp` (`dnsmasq --test` passed; `netstat -tulnp | grep ':53 '` confirmed WAN `eth0` IP no longer bound).
- Hardened `/data/update_duckdns.sh` in-place (preserving `DOMAIN` and `TOKEN` without exposing credentials) with `-m 10` timeout and 50-line `/tmp/duckdns.log` rotation.
- Synchronized `/data/auto_run.sh` with `fpt_daemon.sh`, `flight_recorder.sh`, `iperf3 -s -D`, and deleted 6 obsolete `.bak` / `stats.old.sh` leftovers.

### 3.3 Rust `stats_collector` `v2.1` & Web Dashboard Integration
- Updated `src/stats_collector/stats_collector.rs` (`v2.1`) and cross-compiled with `rustc 1.99.1` (`--target armv7-unknown-linux-musleabihf -C linker=arm-linux-gnueabihf-gcc -C opt-level=z -C strip=symbols`) -> `475 KB` static stripped ARMv7 ELF deployed to `/data/stats_collector` and `/data/www/cgi-bin/stats`:
  - Added `fmt_bytes()` (`KB`/`MB`/`GB`) and extended `services.wireguard` with `active_peers`, `rx_bytes`, `tx_bytes`, `rx_str`, and `tx_str`.
  - Aligned Wired LAN (`type: "laptop"`, `band: "Gigabit LAN"`, `link_proto: "1000BASE-T (1Gbps)"`, `rssi: "Wired"`, `state: "Wired"`) and WireGuard VPN (`type: "vpn"`, `band: "WireGuard VPN"`, `link_proto: "WireGuard (HE160)"`, `rssi: "VPN"`) fields with `/data/www/index.html` UI badge/meter renderers.
- Added `test_wg)` endpoint to `/data/www/cgi-bin/action` and added the **WireGuard VPN (Rust BoringTun)** service card (`#wgStatusBadge`, `#wgPeersText`, `#wgTrafficText`) plus `vpn` icon/meter branches to `/data/www/index.html`.
- Verified live HTTP endpoints on `127.0.0.1:8888`:
  - `/cgi-bin/action?act=test_wg` -> `{"success":true,"msg":"WireGuard Rust BoringTun (PID 2703) đang hoạt động trên cổng UDP 51820! Truyền tải: RX 14.22 MiB / TX 211.57 MiB • DuckDNS: OK"}`.
  - `/cgi-bin/stats` -> valid JSON with live FPT gateway telemetry (`1.079 ms`), `nss.fastpath_byte_pct: 98.6%`, `services.wireguard.tx_str: "211.6 MB"`, `rx_str: "14.2 MB"`, and dynamic `clients` table including `DESKTOP-FH9EA4D` (`Gigabit LAN`) and `WireGuard Peer`.

### 3.4 Security Scan Note
- `snyk_code_scan` was checked earlier on `src/stats_collector` and returned `User not authenticated. Please run 'snyk_auth' first`. SAST scan remains unexecuted pending Snyk MCP authentication.
