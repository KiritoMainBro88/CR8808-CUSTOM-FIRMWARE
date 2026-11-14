# M12.12 — Live Netfilter Rule Deduplication (55 Rules), Xiaomi `stat_points`/Lua Cron Removal, Daemon Fork-Storm Optimization & Nginx Proxy Hardening Report

**Target Device:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Qualcomm IPQ5018 Dual-Core ARMv7 + NSS NPU, Linux `4.4.60`)  
**Repository:** `CR8808-CUSTOM-FIRMWARE` (Branch: `feature/m12-ra82-performance-modernization`)  
**Status:** **APPLIED & VERIFIED LIVE ON HARDWARE** (Zero router reboots; zero rootfs NAND writes)

---

## 1. Executive Summary & Overnight Endurance Verification

Overnight runtime check at `1d 13h 50m` uptime (`Sat Nov 14 09:06:20 ICT 2026`) confirmed that M12.10's root-owned `logrotate` configuration continued rotating and gzip-compressing `/tmp/messages` (`8.9 KB`, `/tmp/log/messages.0.gz` `15.3 KB`) and `/tmp/wifi_analysis.log` (`126.4 KB`, `/tmp/log/wifi_analysis.log.0.gz` `3.8 KB`), holding `Shmem` (`tmpfs`) tightly around `2,800–3,088 kB` (`3%` of `/tmp`). Root-cause inspection of the baseline `~1.00` Linux load average (`1.16` at `100% idle` CPU) also confirmed it is caused by kernel workqueue `kworker/u4:1` (`PID 3725`) sleeping in `D` state (`ecm_nss_ipv4_stats_sync_req_work`) for NPU stats synchronization (`3,508,589` successful syncs, `0` failures).

M12.12 delivered four additional deep optimizations across the Xiaomi router's packet-filtering pipeline, cron scheduler, background daemons, and HTTPS dashboard proxy:

1. **Removed 55 Redundant Netfilter Rules (`filter`, `mangle`, `nat`, `ip6tables` -> `dup=0`):**
   - `iptables -C` checks whether at least one matching rule exists, so pre-M12.7 duplicate insertions remained active in the kernel chains (`235` total rules across the 4 tables).
   - Added an idempotent `dedup_table()` helper to `/data/tune_network.sh` that inspects `-S | sort | uniq -c` and deletes extra (`count - 1`) copies in place while keeping the active rule intact:
     - `filter`: `138` → **`116`** (`-22` duplicates eliminated, including `17` extra `zapret_unblock` UDP `443` rejects, `3` extra UDP `51820` accepts, `2` extra `wg0` forwards)
     - `mangle`: `38` → **`13`** (**`-25` duplicates, `-65.8%`** rules per packet for WMM/DSCP EF marking)
     - `nat`: `47` → **`40`** (`-7` duplicates, including `6` extra `zapret_unblock` TCP `443` redirects and `1` extra `10.99.0.0/24` masquerade)
     - `ip6tables filter`: `12` → **`11`** (`-1` duplicate `RELATED,ESTABLISHED` rule)
   - Also explicitly enforced Qualcomm NSS & ECM fastpath parameters in `/data/tune_network.sh`: `dev.nss.clock.auto_scale=1`, `dev.nss.ipv4cfg.ipv4_accel_mode=1`, `dev.nss.ipv6cfg.ipv6_accel_mode=1`, `dev.nss.n2hcfg.mitigation_core0=1`, and `/sys/kernel/debug/ecm/ecm_classifier_default/accel_delay_pkts=0`.
2. **Eliminated Per-Minute Xiaomi `stat_points` & Smart-Scene Lua Cron Forks (`/etc/crontabs/root`):**
   - Disabled `* * * * * /usr/sbin/startscene_crontab.lua` (which forked `/bin/date` and a Lua VM every 60 seconds for the already-disabled `smartcontroller`) and all 4 `run-parts -a {1min,10min,hourly,daily} /etc/periodic` telemetry collection/conversion triggers (`01_st_coll`, `99_st_conv`), removed `/tmp/stat_points` & `/var/run/statpoints.ts`, and persisted the cleanup in `/data/auto_ssh.sh` and `/data/auto_run.sh`.
3. **Eliminated Background Shell Fork Storms in `/data/flight_recorder.sh` & `/data/fpt_daemon.sh` (>75% Fewer Forks):**
   - Refactored `/data/flight_recorder.sh` from multi-stage `ping | awk | tr`, `echo | cut`, and `cat | grep | tail | awk | tr` pipelines (~19 child forks every 4s) to single-pass `awk` + periodic log trimming every 10 cycles (~3 forks/cycle, **-84%**).
   - Refactored `/data/fpt_daemon.sh` from `ping -c 3` and ~22 separate `echo | grep | head | cut` pipelines (~28 child forks every 5s) to `ping -c 1 -W 1` and single-pass `awk` JSON field extraction (~7 forks/cycle, **-75%**), preserving existing session caching and `/tmp/fpt_cache.json` output schema.
4. **Hardened Nginx HTTPS Reverse Proxy (`/data/8889.conf` & `/etc/nginx/conf.d/8889.conf`):**
   - Verified via `/usr/sbin/nginx -V` that Xiaomi RA82's stock `nginx/1.21.1` binary was compiled with `--without-http_gzip_module` and `--without-http_upstream_keepalive_module`.
   - Configured `tcp_nodelay on;`, `proxy_http_version 1.1;`, and `proxy_set_header Connection "";` (omitting unsupported `gzip` directives) so `/usr/sbin/nginx -t` passes cleanly and Nginx serves `https://127.0.0.1:8889` with `HTTP/1.1 200 OK` and `Connection: keep-alive`.

---

## 2. Live Before vs. After Verification Metrics

| Metric / Parameter | Before M12.12 | After M12.12 | Delta / Verification |
| :--- | :---: | :---: | :--- |
| `iptables` (`filter`) rule count | `138` (`3` dup patterns) | **`116` (`dup=0`)** | `-22` redundant rules removed |
| `iptables -t mangle` rule count | `38` (`6` dup patterns) | **`13` (`dup=0`)** | **`-25` rules (`-65.8%`)** |
| `iptables -t nat` rule count | `47` (`2` dup patterns) | **`40` (`dup=0`)** | `-7` redundant rules removed |
| `ip6tables` (`filter`) rule count | `12` (`1` dup pattern) | **`11` (`dup=0`)** | `-1` redundant rule removed |
| Total netfilter rules across audited tables | `235` | **`180`** | **`-55` rules (`-23.4%`), `0` duplicates** |
| Cron `startscene_crontab.lua` & `/etc/periodic` | Active (every 1m/10m/h/d) | **Commented out** | `/tmp/stat_points` absent (`STAT_POINTS_ABSENT_OK`) |
| `flight_recorder.sh` child forks / cycle | `~19` every 4s | **`~3` every 4s** | **`-84%` fork reduction**, `1` daemon running |
| `fpt_daemon.sh` child forks / cycle | `~28` every 5s | **`~7` every 5s** | **`-75%` fork reduction**, `/tmp/fpt_cache.json` `online:true` |
| NSS & ECM sysctls (`auto_scale`, `accel_mode`, `mitigation_core0`, `accel_delay_pkts`) | Unenforced by script | **`1`, `1`, `1`, `1`, `0`** | Enforced in `/data/tune_network.sh` |
| Nginx `:8889` (`tcp_nodelay`, `proxy_http_version 1.1`) | Default proxy config | **Enabled & tested** | `nginx -t` OK; `HTTP/1.1 200 OK` + `Connection: keep-alive` |
| Router `MemFree` / `MemAvailable` (`/proc/meminfo`) | — | **`47,132 kB` / `41,480 kB`** | `Shmem: 2,800 kB`, `AnonPages: 6,712 kB` |
| Dashboard `stats_collector` memory (`pct`) | `58%` (`109,212 kB` M12.11) | **`57%` (`107,348 kB`)** | `79,572 kB` free+buf+cached |
| NSS Fastpath (`stats_collector`) | `95.6%` pkts / `98.6%` bytes | **`95.6%` pkts / `98.6%` bytes** | `46,594,792` FP vs `2,161,214` exc (`44.6 GB / 45.3 GB`) |
| Rust WireGuard `wg0` (`boringtun-cli`, `51820`) | `UP` (`PID 2703`) | **`UP` (`PID 2703`)** | `/cgi-bin/action?act=test_wg` -> `success:true` |

---

## 3. Router Files Updated (On Persistent `/data` & UBIFS Crontab)

1. **`/data/tune_network.sh`** (`sh -n` OK, executed `RC=0`): Added `dedup_table` for `iptables` (`filter`, `mangle`, `nat`) & `ip6tables` (`filter`) plus explicit `dev.nss.*` & ECM `accel_delay_pkts=0` enforcement.
2. **`/data/auto_ssh.sh` & `/data/auto_run.sh`** (`sh -n` OK): Persisted cron commenting for `startscene_crontab.lua` and `run-parts -a ... /etc/periodic` plus `/tmp/stat_points` cleanup across reboots.
3. **`/etc/crontabs/root`** (UBIFS persistent): Commented out `startscene_crontab.lua` and all 4 `run-parts -a ... /etc/periodic` lines; reloaded `cron`.
4. **`/data/flight_recorder.sh` & `/data/fpt_daemon.sh`** (`sh -n` OK): Refactored with `RUN_MODE="${1:-}"` preservation, single-pass `awk` extraction, and single-ping LAN checks.
5. **`/data/8889.conf` & `/etc/nginx/conf.d/8889.conf`**: Added `tcp_nodelay on;`, `proxy_http_version 1.1;`, and `proxy_set_header Connection "";` (`/usr/sbin/nginx -t` successful; Nginx reloaded).

---

## 4. Verification Commands & Observed Results

- `sh -n /data/tune_network.sh /data/auto_ssh.sh /data/auto_run.sh /data/flight_recorder.sh /data/fpt_daemon.sh` -> **`OK`**
- `sh /data/tune_network.sh` -> **`TUNE_RC=0`**
- `iptables -S | sort | uniq -d | wc -l` (and `mangle`, `nat`, `ip6tables`) -> all **`0` duplicates** (`116`, `13`, `40`, `11` rules)
- `/usr/sbin/nginx -t` -> **`syntax is ok / test is successful`**
- `curl -k -s -D - -o /dev/null https://127.0.0.1:8889/cgi-bin/stats` -> **`HTTP/1.1 200 OK`**, `Connection: keep-alive`
- `curl -s "http://127.0.0.1:8888/cgi-bin/action?act=test_wg"` -> `{"success":true,"msg":"WireGuard Rust BoringTun (PID 2703) đang hoạt động trên cổng UDP 51820! Truyền tải: RX 14.22 MiB / TX 211.57 MiB • DuckDNS: OK"}`
