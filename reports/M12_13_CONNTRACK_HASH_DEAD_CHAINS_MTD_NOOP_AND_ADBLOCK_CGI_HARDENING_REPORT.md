# M12.13 — Conntrack Hash/ALG/Checksum Tuning, Dead Netfilter Chain Pruning, MTD Flash `noop` Scheduler & AdBlock/CGI Hardening Report

**Target Device:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Qualcomm IPQ5018 Dual-Core ARMv7 + NSS NPU, Linux `4.4.60`)  
**Repository:** `CR8808-CUSTOM-FIRMWARE` (Branch: `feature/m12-ra82-performance-modernization`)  
**Status:** **APPLIED & VERIFIED LIVE ON HARDWARE** (Zero router reboots; zero rootfs NAND writes)

---

## 1. Executive Summary

M12.13 targeted kernel connection-tracking efficiency, disabled-module netfilter chain jumps, NAND flash I/O scheduling, atomic AdBlock list validation, and dashboard CGI reliability + UBIFS flash deduplication inside the Xiaomi router:

1. **Conntrack Hash Table Expansion & Redundant Inspection Removal (`/data/tune_network.sh`):**
   - Expanded `/sys/module/nf_conntrack/parameters/hashsize` from `2920` (`nf_conntrack_buckets = 3072`) to **`8192`** (`+166.7%` buckets for `nf_conntrack_max = 32768`, cutting average chain depth per bucket).
   - Disabled automatic L7 ALG helper payload scanning (`net.netfilter.nf_conntrack_helper = 0`, down from `1`).
   - Disabled redundant software L4 checksum recomputation inside netfilter (`net.netfilter.nf_conntrack_checksum = 0`, down from `1`) since NIC/Wi-Fi drivers handle checksums.
   - Enabled liberal TCP sequence window tracking (`net.netfilter.nf_conntrack_tcp_be_liberal = 1`, up from `0`) to avoid false `INVALID` drops across Qualcomm NSS (`qca-nss-ecm`) flow offload transitions.
2. **Pruned 8 Dead Netfilter Rules & Unconditional Factory Chain Jumps:**
   - Because UCI had `parentalctl.global.disabled='1'` and `upnpd.config.disable_upnp='1'`, `fw3` still left live chain jumps in hot packet paths (`zone_lan_forward` -> `parentalctl_device_filter` / `parentalctl_host_filter`, `nat zone_lan_prerouting` -> `parentalctl_nat`, `zone_wan_forward` -> `MINIUPNPD`, `nat zone_wan_prerouting` -> `MINIUPNPD`).
   - Xiaomi's factory dummy `macfilter_wan` placeholder rule and empty `macfilter_input` jump were also executed on every forwarded/LAN input packet.
   - Added idempotent removal in `/data/tune_network.sh` whenever those modules remain disabled/empty, reducing `iptables -S` from `116` -> **`110`** lines and `iptables -t nat -S` from `40` -> **`38`** lines.
3. **Switched All 24 NAND Flash Block Queues (`mtdblock0..23`) from HDD `deadline` to `noop`:**
   - Switched `/sys/block/mtdblock*/queue/scheduler` to **`[noop]`** and `rq_affinity` to **`2`** (`non_noop_mtdblocks=0`) to avoid rotational elevator sorting on flash blocks.
4. **Atomic Game-Safe `/data/adblock/update.sh`, Robust `/data/www/cgi-bin/action` & `/data` UBIFS Symlink Deduplication:**
   - Converted `/data/www/cgi-bin/stats` (`474.8 KB` duplicate ELF) into a symlink to `/data/stats_collector` and removed unreferenced `/data/fpt_query.sh`, shrinking `/data` UBIFS usage from `3,112 KB (7%)` to **`2,680 KB (6%, 42,992 KB free)`**.
   - Rewrote `/data/adblock/update.sh` with `--connect-timeout 10 -m 30`, temporary staging, expanded game/CDN whitelist (`qq.com`, `tencent`, `proximabeta`, `levelinfinite`, `igamecj`, `garena`, `freefire`, `hoyoverse`, `mihoyo`, `yuanshen`, `starrails`, `zenlesszonezero`, `riotgames`, `playvalorant`, `leagueoflegends`, `pvp.net`, `vnggames`, `zing.vn`, `steampowered`, `steamcommunity`, `steamstatic`, `roblox`), `>5000` rule count guard, `dnsmasq --test` check with rollback, and `/etc/init.d/dnsmasq restart`. Stripped `36` previously blocked gaming/CDN entries from the live list (`18,461` -> **`18,425`** rules) and reloaded `dnsmasq`.
   - Fixed `/data/www/cgi-bin/action` so `renew_fpt_ip` automatically re-authenticates when `/tmp/fpt_sid.tmp` has an expired session token, and added `</dev/null` stdin closure on background subshells (`update_adblock`, `auto_hunt_ip`, `clear_flight_log`).

---

## 2. Live Before vs. After Verification Metrics

| Metric / Parameter | Before M12.13 | After M12.13 | Delta / Verification |
| :--- | :---: | :---: | :--- |
| `/sys/module/nf_conntrack/parameters/hashsize` | `2920` (`3072` buckets) | **`8192`** (`8192` buckets) | **`+166.7%` bucket count** |
| `net.netfilter.nf_conntrack_helper` | `1` | **`0`** | Legacy ALG payload scan disabled |
| `net.netfilter.nf_conntrack_checksum` | `1` | **`0`** | Redundant SW checksum disabled |
| `net.netfilter.nf_conntrack_tcp_be_liberal` | `0` | **`1`** | Safe across NSS flow handoffs |
| `iptables -S` total lines (`filter`) | `116` | **`110`** | Dead `parentalctl`, `MINIUPNPD`, `macfilter` jumps removed |
| `iptables -t nat -S` total lines (`nat`) | `40` | **`38`** | Dead `parentalctl_nat`, `MINIUPNPD` jumps removed |
| `mtdblock0..23` I/O scheduler / `rq_affinity` | `[deadline]` / `1` | **`[noop]` / `2`** | `non_noop_mtdblocks=0` (all 24 verified) |
| `/data/www/cgi-bin/stats` storage | Duplicate `474.8 KB` ELF | **Symlink -> `/data/stats_collector`** | Single UBIFS inode & pagecache |
| `/data` UBIFS used (`df -k /data`) | `3,112 KB` (`7%`) | **`2,680 KB` (`6%`)** | **`-432 KB` freed** (`42,992 KB` free) |
| AdBlock active rules (`adblock.blocked_count`) | `18,461` | **`18,425`** | `36` game/CDN domains unblocked & validated |
| `/cgi-bin/action?act=test_wg` | `success:true` | **`success:true`** | Rust BoringTun `PID 2703`, UDP `51820` |
| `/cgi-bin/action?act=test_steam` | — | **`success:true`** | `Steam Store IP: 104.83.198.104` (`11` IPSet IPs) |
| `stats` JSON (`temp`, `nss`, `memory`) | `71°C`, `57%` | **`69°C`**, `95.6%` FP / `98.6%` B, `57%` | Healthy `1d 14h 6m` uptime |

---

## 3. Verification Commands & Observed Results

- `sh -n /data/tune_network.sh && sh /data/tune_network.sh` -> **`SYNTAX_OK`**, **`TUNE_RC=0`**
- `sh -n /data/adblock/update.sh && sh -n /data/www/cgi-bin/action` -> **`STEP2_SYNTAX_OK`**
- `cat /sys/module/nf_conntrack/parameters/hashsize` & `sysctl net.netfilter.nf_conntrack_buckets` -> **`8192`**
- `FILTER_DEAD_JUMPS_GONE_OK` / `NAT_DEAD_JUMPS_GONE_OK`
- `for q in /sys/block/mtdblock*/queue/scheduler ...` -> **`non_noop_mtdblocks=0`**
- `ls -l /data/www/cgi-bin/stats` -> **`-> /data/stats_collector`**; `df -k /data` -> **`2680 / 48168 (6%)`**
- `curl -s http://127.0.0.1:8888/cgi-bin/stats` -> valid JSON (`uptime: 1d 14h 6m`, `temp: 69`, `disk.pct: 6`, `adblock.blocked_count: 18425`)
- `curl -s "http://127.0.0.1:8888/cgi-bin/action?act=test_wg"` & `act=test_steam` -> both **`"success":true`**
