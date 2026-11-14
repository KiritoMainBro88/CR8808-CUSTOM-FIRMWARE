# M12.14 — SMP IRQ Rebalance (`CPU1` Offload), UCI `802.11k/v` Persistence, FPT Auto-Hunter Session Fix & Rust `stats_collector` v2.2 Upgrade Report

**Target Device:** Xiaomi CR8808 Ver.B / AX3000 (`RA82 v1.4.31`, Qualcomm IPQ5018 Dual-Core ARMv7 + NSS NPU, Linux `4.4.60`)  
**Repository:** `CR8808-CUSTOM-FIRMWARE` (Branch: `feature/m12-ra82-performance-modernization`)  
**Status:** **APPLIED & VERIFIED LIVE ON HARDWARE** (Zero router reboots; zero rootfs NAND writes)

---

## 1. Executive Summary

M12.14 targeted hardware interrupt contention on `CPU0`, kernel serial console latency, persistent Wi-Fi `802.11k/v` configuration, upstream ONT PPPoE session recovery in the latency hunter bot, and real-time client/memory telemetry accuracy in the Rust dashboard daemon:

1. **Symmetric Multi-Core IRQ Rebalance (`/data/tune_network.sh`) & Verbose Serial `printk` Suppression:**
   - Isolated `CPU0` (`smp_affinity = 1`) exclusively for the primary NSS NPU packet queue (`IRQ 28 nss_queue0`, `145.9M+` cumulative interrupts), and moved **all 13 auxiliary DMA, NSS buffer refill, Copy Engine, and PCIe WLAN interrupts** (`24 bam_dma`, `25 nss_empty_buf_sos`, `26 nss_empty_buf_queue`, `29 nss_queue1`, `40 ce1`, `41 ce2`, `42 ce3`, `69 ppdu-end-interrupts-mac1`, `78 rxdma2host-destination-ring-mac1`, `91 pci0_wlan_ce_1`, `92 pci0_wlan_ce_2`, `93 pci0_wlan_ce_3`, `98 pci0_wlan_grp_dp_3`) onto `CPU1` (`smp_affinity = 2`).
   - Removed the conflicting M12.10 `echo 1` writes for IRQs `25` and `40` so re-running `/data/tune_network.sh` never bounces interrupts between cores.
   - Reduced `/proc/sys/kernel/printk` from `7 4 1 7` (debug serial output) to **`4 4 1 7`**, preventing debug UART stalls on `IRQ 20 (msm_serial0)`.
   - Over a live 4-second hardware measurement window, **`100%` of new `TASKLET` SoftIRQs (`+834` vs `+0` on `CPU0`) and `100%` of auxiliary NSS/CE/WLAN interrupts executed on `CPU1`**.

2. **Persistent `802.11k/v` (`rrm` / `wnm`) in UCI (`/etc/config/wireless`):**
   - Previously, `rrm='0'` and `wnm='0'` in UCI forced `/data/tune_network.sh` to patch `wl0` and `wl1` dynamically via `iwpriv` after boot.
   - Updated `wireless.@wifi-iface[0]` (`wl1`) and `wireless.@wifi-iface[1]` (`wl0`) to `rrm='1'` and `wnm='1'` and ran `uci commit wireless` without restarting `hostapd`.

3. **FPT Auto-Hunter Bot Session Recovery & PPPoE Poll Fix (`/data/fpt_auto_hunter.sh`):**
   - **Expired Session Self-Healing:** Added `do_login()` and `ubus_call()` so both `get_wan_ip()` and `reconnect()` detect HTTP/ubus `"error"` responses from `http://192.168.100.1/ubus`, clear stale `/tmp/fpt_sid.tmp`, re-authenticate automatically, and retry the RPC call.
   - **PPPoE Negotiation Poll Loop:** Replaced the hardcoded `sleep 6` wait after `reconnect_pppoe` with up to `5` polling checks (`sleep 3`, up to `15s` total) until a non-empty IPv4 WAN address is returned, followed by `sleep 2` before latency measurement.
   - **Accurate Single-Pass `awk` Ping Parsing:** BusyBox `ping` prints `round-trip min/avg/max = X/Y/Z ms`; previous `awk -F'/' 'END{printf "%.1f", $5}'` read `MAX` (`$5`) instead of `AVG` (`$4`) and spawned `cut`. Replaced with single-pass `awk -F'/' '/round-trip|rtt/ {printf "%.0f\n", ($1 ~ /rtt/ ? $5 : $4); exit}'`.

4. **Rust `stats_collector` `v2.2` Upgrade (`src/stats_collector/stats_collector.rs` -> `/data/stats_collector`):**
   - **`SReclaimable` Memory Accounting:** Added parsing of `SReclaimable:` from `/proc/meminfo` (`avail_sum = free + buffers + cached + sreclaimable`), accurately crediting `4,376 kB` of reclaimable kernel slab cache (`free_kb: 82,204 kB`, `used_kb: 104,716 kB`, `pct: 56%`).
   - **Live `wl13` IoT AP RF Telemetry:** Added `("wl13", "2.4GHz (IoT)", "802.11n (HT20)", "Wi-Fi 4 (IoT)", "HT20 (2.4GHz)")` with `type: "iot"` to the `wlanconfig` inspection loop. Live 2.4 GHz IoT clients (`192.168.32.127`) now report real PHY/RF rates (`tx: 43M`, `rx: 39M`, `rssi: -61 dBm`, `snr: 34 dB`) instead of falling back to hardcoded ARP stubs (`72M / -48 dBm / 40 dB`).
   - **Accurate `HE80` vs `HE160` Detection & Dynamic SNR:** Distinguished `IEEE80211_MODE_11AXA_HE80` from `HE160` for both `link_proto` and `phy_mode`, and replaced hardcoded `"54 dB"` SNR with `(rssi_val - (-95)).clamp(5, 60)` matching Qualcomm `wlanconfig` SNR calculation within `1 dB`.

---

## 2. Live Before vs. After Verification Metrics

| Metric / Parameter | Before M12.14 | After M12.14 | Delta / Verification |
| :--- | :---: | :---: | :--- |
| `smp_affinity` (`24, 25, 40, 42, 93`) | `3 / 1 / 1 / 3 / 3` (`CPU0`-heavy) | **`2` (all pinned to `CPU1`)** | Offloaded cleanly from `CPU0` |
| `smp_affinity` (`26, 29, 41, 69, 78, 91, 92, 98`) | `2` (`CPU1`) | **`2` (all enforced in `tune_network.sh`)** | Includes `irq 93`, removes `25`/`40` bounce |
| `smp_affinity` (`28 nss_queue0`) | `1` (`CPU0`) | **`1` (dedicated `CPU0`)** | `CPU0` `+4,298` / `CPU1` `+0` (4s sample) |
| Auxiliary IRQs (`24, 25, 26, 29, 40-42, 69, 78, 91-93, 98`) 4s `CPU0` delta | Mixed `CPU0` hits (`10M+` historical) | **`+0` on `CPU0`** (`+1,559` on `CPU1`) | `100%` handled by `CPU1` |
| `TASKLET` SoftIRQ 4s delta (`CPU0` / `CPU1`) | `20.79M` (`80.1%`) on `CPU0` | **`CPU0: +0` / `CPU1: +834`** | **`100%` offloaded to `CPU1`** |
| `/proc/sys/kernel/printk` | `7 4 1 7` (`KERN_DEBUG`) | **`4 4 1 7`** (`KERN_WARNING`) | `IRQ 20 (msm_serial0)`: `+0` during sample |
| UCI `wireless.@wifi-iface[0..1].{rrm,wnm}` | `'0'` | **`'1'`** (`uci commit wireless`) | Persists `802.11k/v` across reboots |
| `/data/fpt_auto_hunter.sh` expired SID test | Fails silently on stale SID | **`EXPIRED_SID_RECOVERY=VALID_IPV4`** | Auto-refreshes `32`-char SID via `do_login()` |
| `stats_collector` HE80 client (`192.168.31.149`) | Mislabeled `HE160 (160MHz)`, `snr: 54 dB` | **`HE80 (80MHz)`**, `720M/960M`, `-48 dBm`, `47 dB` | Matches `wlanconfig wl0 list sta` |
| `stats_collector` HE160 client (`192.168.31.101`) | `HE160 (160MHz)`, `snr: 54 dB` | **`HE160 (160MHz)`**, `2401M/2401M`, `-42 dBm`, `53 dB` | Dynamic SNR (`rssi + 95`) |
| `stats_collector` `wl13` IoT (`192.168.32.127`) | ARP fallback `72M`, `-48 dBm`, `40 dB` | **`43M / 39M`**, `-61 dBm`, `34 dB`, `HT20/40 (2.4GHz)` | Real `wlanconfig wl13 list sta` telemetry |
| `stats_collector` `/proc/meminfo` `SReclaimable` | Ignored | **Included (`4,376 kB`)** | `free_kb: 82,204`, `used_kb: 104,716` (`56%`) |
| SoC Temp / `/data` UBIFS / `nss` | `69°C` / `6%` | **`68°C`**, `2.6M / 47.0M (6%)` | `95.6%` FP packets / `98.6%` FP bytes (`1d 14h 22m`) |

---

## 3. Verification Commands & Observed Results

- `sh -n /data/tune_network.sh && /data/tune_network.sh` -> exit `0`; `cat /proc/sys/kernel/printk` -> `4 4 1 7`; `/proc/irq/{24,25,26,29,40,41,42,69,78,91,92,93,98}/smp_affinity` -> `2`, `/proc/irq/28/smp_affinity` -> `1`.
- `uci show wireless | grep -E 'rrm|wnm'` -> `rrm='1'` and `wnm='1'` on both `@wifi-iface[0]` and `@wifi-iface[1]`.
- `sh -n /data/fpt_auto_hunter.sh` -> **`SYNTAX_OK`**; expired-SID recovery check (`echo "expired_bogus_sid_test" > "$SID_FILE" && get_wan_ip`) -> **`EXPIRED_SID_RECOVERY=VALID_IPV4`**, **`SID_LEN=32`**.
- `~/.cargo/bin/rustc --target armv7-unknown-linux-musleabihf -C opt-level=z -C strip=symbols -C linker=arm-linux-gnueabihf-gcc .../stats_collector.rs` -> exit `0`, `486,176` bytes static stripped ARM EABI5 ELF (`sha256: 6aff54a7c52118a1d96e65a5fd438e006f7d77070bcbb90493ad047bcbf5a6cb`).
- `curl -k -s https://127.0.0.1:8889/cgi-bin/stats` -> **`HTTP=200 SIZE=3473`**, serving updated `/tmp/stats.json` from symlink `/data/www/cgi-bin/stats -> /data/stats_collector` (`PID 1003`).
- `snyk_code_scan` on `src/stats_collector` -> invoked per security rule; Snyk MCP reported `User not authenticated. Please run 'snyk_auth' first` (static scan unexecuted pending local Snyk auth).
