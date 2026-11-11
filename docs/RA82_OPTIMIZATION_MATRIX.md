# RA82 Optimization & Enhancement Matrix (Track A Master Classification)

- **Document ID:** `docs/RA82_OPTIMIZATION_MATRIX.md`
- **Target Device:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Firmware Baseline:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit ARMv7, 256MB DDR3L, 128MB SPI NAND)
- **Authority:** Chief Architect Directive M11.0.2 / Lead Systems Engineer (Gemini)
- **Safety Boundary:** **STRICT NO-GO FLASH | ZERO NAND WRITES | ZERO NVRAM EDITS | ZERO REBOOTS**
- **Status:** **PREFLIGHT REVIEW ONLY — ZERO UNSANCTIONED DEVICE EXECUTION**

---

## 1. Executive Summary & Disposition Overview

Each optimization candidate has been evaluated against empirical device readback, kernel source code mechanics, memory safety, performance impact, and reversibility.

```
+----------------------------------------------------------------------------------------------------------------+
|                                    MASTER OPTIMIZATION DISPOSITION SUMMARY                                     |
+-------------+----------------------------------------------+------------+--------------------------------------+
| Identifier  | Optimization Area                            | Decision   | Primary Technical Justification      |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-SEC-01  | WAN SSH (Dropbear port 56789) Restriction    | GO         | Severe security exposure; safe       |
|             |                                              |            | volatile iptables rule with rollback |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-VPN-01  | BoringTun Rust Sandbox Trial (wg1 / 51821)   | HOLD       | Low risk; isolated sandbox; ready to |
|             |                                              |            | benchmark once authorized            |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-VPN-02  | BoringTun Production Cutover (wg0 / 51820)   | HOLD       | Blocked until OPT-VPN-01 completes   |
|             |                                              |            | and passes 100% acceptance criteria  |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-CPU-01  | Receive Packet Steering (RPS) on Non-NSS     | HOLD       | Cumulative softirq != live overload; |
|             |                                              |            | must profile deltas before testing   |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-RAM-01  | Xiaomi Cloud / Vendor Daemons Reclamation    | HOLD       | Genuine RssAnon is only ~6.8 MB;     |
|             |                                              |            | potential breakage of UI/management  |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-WIFI-01 | Wi-Fi 6 OFDMA / MU-MIMO Optimization         | HOLD       | Active STA reports "MU capable: No"; |
|             |                                              |            | driver tuning without client is moot |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-WIFI-02 | Wi-Fi Roaming (802.11k/v) Optimization       | HOLD       | Single AP topology; zero roaming     |
|             |                                              |            | target exists on local premises      |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-DNS-01  | DNS Latency Tuning & DoH/DoT via dnsproxy    | HOLD       | Existing dnsproxy in /data; needs    |
|             |                                              |            | benchmark vs dnsmasq baseline        |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-QOS-01  | QoS / SQM Bufferbloat Mitigation (CAKE)      | REJECT     | CAKE forces NSS bypass, collapsing   |
|             |                                              |            | 1 Gbps wire speed to ~400-500 Mbps   |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-TCP-01  | Conntrack Timeout Reduction                  | REJECT     | Conntrack table utilization is only  |
|             |                                              |            | 3.37%; premature drops break sockets |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-TCP-02  | TCP Window / Socket Buffer Shrinking         | REJECT     | Violates Bandwidth-Delay Product     |
|             |                                              |            | (BDP = 2.5 MB) on Gigabit WAN        |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-KRN-01  | Live Kernel Binary Upgrade / Patching        | REJECT     | Requires kernel rebuild & NAND flash |
|             |                                              |            | violating STRICT NO-GO FLASH mandate |
+-------------+----------------------------------------------+------------+--------------------------------------+
| OPT-USR-01  | Standalone Userspace Modernization in /data  | HOLD       | Statically linked ARMv7 binaries     |
|             |                                              |            | viable in userdisk without flash     |
+-------------+----------------------------------------------+------------+--------------------------------------+
```

---

## 2. Detailed Technical Profiles for Each Candidate

### 2.1 OPT-SEC-01: WAN SSH (Dropbear Port 56789) Restriction
- **Classification:** **`GO`** (Highest Priority Security Hardening)
- **Existing Evidence:** `reports/M11_RA82_LIVE_AUDIT_RAW.txt` confirms Dropbear is running with `PasswordAuth 'on'` and `RootPasswordAuth 'on'` on port `56789`. `iptables -L zone_wan_input -v -n` confirms rule jumping to `input_wan_rule` with 7 recorded packets hitting the accept rule.
- **Topology Context:** Router WAN IP is `192.168.100.75` (RFC1918) behind an ISP ONT (`192.168.100.1`). Although behind double-NAT, exposure persists if ONT has DMZ/port-forwarding enabled, or if rogue devices/technicians on the `192.168.100.0/24` subnet attempt brute-force root logins.
- **Expected Benefit:** Complete elimination of remote brute-force attack surface from WAN and upstream ONT subnet.
- **Resource Cost:** 0 kB RAM, 0% CPU. Single netfilter rule evaluation.
- **Implementation Method:** Volatile iptables rule in RAM:
  ```sh
  iptables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP
  ```
- **Measurement Procedure:**
  1. From LAN (`192.168.31.x`): `ssh -p 56789 -o ConnectTimeout=5 root@192.168.31.1` must succeed (exit code 0).
  2. From WAN / upstream network (`192.168.100.x`): `nc -z -w 3 192.168.100.75 56789` must timeout / fail.
- **Risk:** Zero risk to LAN connectivity. Packets on `br-lan` traverse `zone_lan_input`, not `zone_wan_input`.
- **Rollback Strategy (Automatic Watchdog):**
  Arm an automated background rollback timer prior to rule execution:
  ```sh
  (sleep 180; iptables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null) &
  ```
- **Hardware Dependencies:** None.

---

### 2.2 OPT-VPN-01: BoringTun Rust Isolated Sandbox Trial (`wg1` / UDP 51821)
- **Classification:** **`HOLD`** (Ready for sandbox test upon explicit authorization)
- **Existing Evidence:** WireGuard Go (`/data/wg_server`) on `wg0` consumes 523 MB virtual address space (`VSZ`). A standalone BoringTun 0.7.1 binary already exists at `/tmp/boringtun_test` (1.65 MB).
- **Target ABI Verification:** Stock RA82 kernel is 32-bit `armv7l` (ARM Cortex-A53 running in AArch32 mode, Linux 4.4.60). BoringTun must be compiled for `armv7-unknown-linux-musleabihf` (statically linked, `-C target-feature=+crt-static`) with `signalfd` fallback patch.
- **Expected Benefit:** Empirically validate BoringTun stability, signalfd fallback, memory footprint ($\le 4.0\text{ MB}$ RSS), and crypto performance on physical ARMv7 without impacting production VPN.
- **Resource Cost:** ~3.0–3.5 MB RAM for temporary sandbox process.
- **Implementation Method:**
  1. Create temporary directory `/tmp/wg1_sandbox`.
  2. Spawn BoringTun on virtual interface `wg1` listening on port `51821 UDP`.
  3. Assign IP `10.99.1.1/24` to `wg1`.
  4. Connect test client to `51821 UDP`.
- **Measurement Procedure:**
  1. Test handshake completion and keepalive stability over 15 minutes.
  2. Run bidirectional ping (`ping -c 100 10.99.1.2`).
  3. Measure `VmRSS` and `RssAnon` from `/proc/<PID>/status`.
- **Risk:** Zero. `wg0` (Go) remains untouched on port 51820.
- **Rollback Strategy:** `killall boringtun_test; ip link del wg1 2>/dev/null; rm -rf /tmp/wg1_sandbox`.
- **Hardware Dependencies:** Linux TUN driver (`/dev/net/tun`).

---

### 2.3 OPT-VPN-02: BoringTun Production Cutover (`wg0` / UDP 51820)
- **Classification:** **`HOLD`** (Blocked until OPT-VPN-01 passes 100% acceptance criteria)
- **Existing Evidence:** Dependent on successful completion of OPT-VPN-01.
- **Expected Benefit:** Permanent reclamation of ~20 MB physical RAM (`RssAnon`) and 513 MB virtual memory. Long-term memory safety (Rust).
- **Resource Cost:** Net reduction of ~20 MB RAM.
- **Implementation Method:**
  1. Stop `/data/wg_server`.
  2. Launch production BoringTun binary on `wg0` port 51820.
  3. Restore routing and firewall rules.
- **Measurement Procedure:** Sustained 60-minute soak test with active client traffic; verify zero packet loss and zero memory leakage.
- **Risk:** Medium. Interruption of VPN tunnel if handshake fails.
- **Rollback Strategy:** Immediate respawn of `/data/wg_server` with original keys.
- **Hardware Dependencies:** None.

---

### 2.4 OPT-CPU-01: Receive Packet Steering (RPS) on Non-NSS Interfaces
- **Classification:** **`HOLD`** (Profiling required before trial)
- **Existing Evidence:** Cumulative `/proc/softirqs` showed CPU0 handled 234.5M `NET_RX` events vs 0.97M on CPU1 (99.58% on CPU0 over 2.24 days). All queues have `rps_cpus: 0`.
- **Counter-Evidence & Mechanism:** The 99.58% figure is cumulative history, not instantaneous saturation. 96.85% of transit traffic is offloaded to Qualcomm NSS hardware and never touches Linux softirqs. Software path is only exercised by VPN, local sockets, and proxies.
- **Expected Benefit:** Potential distribution of CPU-heavy VPN cryptography or TCP checksums across CPU0 and CPU1.
- **Resource Cost:** Inter-Processor Interrupt (IPI) overhead and L1 instruction/data cache line bouncing between cores.
- **Implementation Method:**
  ```sh
  echo 2 > /sys/class/net/wg0/queues/rx-0/rps_cpus
  ```
- **Measurement Procedure:** Run `scripts/measure_cpu_deltas.sh 30` during high-throughput VPN transfer.
- **Acceptance Threshold:** Trial justified ONLY IF CPU0 softirq exceeds 80% utilization while CPU1 is $<20\%$.
- **Risk:** High risk of TCP packet reordering, cache thrashing, and increased latency if applied indiscriminately.
- **Rollback Strategy:** `echo 0 > /sys/class/net/wg0/queues/rx-0/rps_cpus`.
- **Hardware Dependencies:** None.

---

### 2.5 OPT-RAM-01: Xiaomi Cloud / Vendor Daemons Reclamation
- **Classification:** **`HOLD`** (Audit RssAnon before service intervention)
- **Existing Evidence:** Process listing reveals 4 non-standard vendor daemons:
  - `messagingagent` (PID 1809): VSZ 6,836 KB, estimated RssAnon ~2.8 MB.
  - `trafficd` (PID 2420): VSZ 3,456 KB, estimated RssAnon ~1.5 MB.
  - `cab_meshd` (PID 1382): VSZ 2,828 KB, estimated RssAnon ~1.4 MB.
  - `smartcontroller` (PID 2510): VSZ 2,120 KB, estimated RssAnon ~1.1 MB.
- **Functional Dependency Analysis:**
  - `messagingagent`: Disabling terminates MiWiFi mobile app cloud pairing and auto-update checks.
  - `trafficd`: Disabling breaks real-time bandwidth reporting in the Web UI.
  - `cab_meshd`: Disabling closes TCP/UDP ports 19553 and 35530. Required only if mesh nodes are paired.
  - `smartcontroller`: Disabling terminates Xiaomi IoT quick-pairing protocol.
- **Expected Benefit:** Reclaiming at most $\sim 6.8\text{ MB}$ of actual physical RAM.
- **Resource Cost:** Loss of corresponding Web UI features, mobile app management, or mesh coordination.
- **Risk:** Medium to High. Potential hidden dependencies in Xiaomi's proprietary scripts (e.g., `trafficd` feeds QoS).
- **Rollback Strategy:** Restarting daemon from `/usr/bin/` or `/usr/sbin/`.
- **Hardware Dependencies:** None.

---

### 2.6 OPT-WIFI-01: Wi-Fi 6 OFDMA / MU-MIMO Parameter Optimization
- **Classification:** **`HOLD`** (Client limitation blocker)
- **Existing Evidence:** Readback proves 5 GHz radio (`wl0` / QCN6102) is operating at full 160 MHz bandwidth (Channel 40) with active station connected at 2,401.9 Mbps (MCS 11). However, connected station explicitly reports: `MU capable: No`.
- **Expected Benefit:** Negligible on single non-MU client. OFDMA benefits dense multi-client environments.
- **Resource Cost:** Tuning proprietary QSDK `iwpriv` parameters can cause beacon instability or association drops.
- **Risk:** High risk of client disconnection or Wi-Fi driver panic.
- **Rollback Strategy:** `wifi reload`.
- **Hardware Dependencies:** Requires client stations with Wi-Fi 6 DL/UL MU-MIMO and OFDMA support.

---

### 2.7 OPT-WIFI-02: Wi-Fi Roaming (802.11k/v) Optimization
- **Classification:** **`HOLD`** (Topology limitation blocker)
- **Existing Evidence:** Network has a single AP (`192.168.31.1`). No secondary mesh AP or repeater exists.
- **Expected Benefit:** 802.11k (RRM) and 802.11v (BTM) provide neighbor reports and BSS transition steering. Without neighbor BSSIDs, steering frames are rejected by client STAs.
- **Risk:** Sending unsolicited BTM requests to clients without alternative BSS targets can trigger client Wi-Fi disconnections.
- **Rollback Strategy:** Disable `rrm` and `wnm` in `/etc/config/wireless`.
- **Hardware Dependencies:** Multi-AP deployment.

---

### 2.8 OPT-DNS-01: DNS Latency Tuning & DoH/DoT Integration via `dnsproxy`
- **Classification:** **`HOLD`** (Requires comparative latency benchmark)
- **Existing Evidence:** Audit found `/data/dnsproxy` (11.4 MB executable) and `dnsmasq` listening on port 53. Upstream queries currently resolve through ISP DNS via `/tmp/resolv.conf.auto`.
- **Expected Benefit:** Encrypted DNS (DoH/DoT) prevents ISP DNS hijacking and tracking. DNS caching reduces lookup latency from 20–50ms to $<1\text{ms}$ for repeat queries.
- **Resource Cost:** `dnsproxy` requires ~15–20 MB RAM if launched; `dnsmasq` cache expansion requires $<500\text{ KB}$ RAM.
- **Implementation Method:** Expand dnsmasq internal cache size to `cache-size=2048` in `/etc/dnsmasq.conf`.
- **Measurement Procedure:** Host-side `dig` / `nslookup` benchmarking: 100 consecutive queries measuring minimum, mean, and maximum response times.
- **Risk:** Low. If upstream DNS fails, internet appears offline to users.
- **Rollback Strategy:** Revert dnsmasq config to default.
- **Hardware Dependencies:** None.

---

### 2.9 OPT-QOS-01: QoS / SQM Bufferbloat Mitigation (CAKE / fq_codel)
- **Classification:** **`REJECT`** (Fundamental Architectural Incompatibility)
- **Existing Evidence & Mechanism:** Qualcomm NSS hardware acceleration intercepts IP packets at the driver ingress level and performs hardware NAT/routing directly, completely bypassing Linux traffic control (`tc` / `qdisc`).
- **Conflict:** To enable CAKE or fq_codel, NSS hardware offload must be disabled for all routed flows (`is_bypassed = 0` in ECM). Disabling NSS forces 1 Gbps routing into the 1.0 GHz Cortex-A53 dual-core host CPU.
- **Performance Impact:** Pure software routing with CAKE pegs CPU0 at 100% and throttles throughput from 940 Mbps down to ~400–500 Mbps.
- **Conclusion:** Banning NSS to achieve bufferbloat shaping on a 1 Gbps symmetrical link is a net negative. Rejected.

---

### 2.10 OPT-TCP-01: Conntrack Timeout Reduction
- **Classification:** **`REJECT`** (Unwarranted & Hazardous)
- **Existing Evidence:** Live audit confirms conntrack table usage is **552 entries out of 16,384** (3.37% capacity).
- **Risk:** Lowering `nf_conntrack_tcp_timeout_established` from 432,000s (5 days) down to 3,600s or lower causes long-lived idle connections (SSH sessions, WebSocket streams, IoT MQTT connections, database pools) to be abruptly dropped, triggering connection resets and retransmissions.
- **Conclusion:** With 96.63% table headroom, shrinking timeouts provides zero measurable RAM savings while introducing connection instability. Rejected.

---

### 2.11 OPT-TCP-02: TCP Window / Socket Buffer Shrinking
- **Classification:** **`REJECT`** (Violates Bandwidth-Delay Product)
- **Existing Evidence & Formula:** The Bandwidth-Delay Product (BDP) dictates the minimum buffer size required to sustain full throughput:
  $$\text{BDP} = \text{Bandwidth} \times \text{RTT}$$
  For 1,000 Mbps WAN with 20ms round-trip latency:
  $$\text{BDP} = 1,000,000,000\text{ bps} \times 0.020\text{ s} = 20,000,000\text{ bits} = 2.5\text{ Megabytes}$$
- **Performance Impact:** Shrinking `rmem_max` or `wmem_max` to "save RAM" physically caps single-stream TCP throughput well below 1 Gbps.
- **Conclusion:** Memory savings of ~1–2 MB at the cost of capping gigabit performance is unacceptable. Rejected.

---

### 2.12 OPT-KRN-01: Live Kernel Binary Upgrade / Backporting
- **Classification:** **`REJECT`** (Violates STRICT NO-GO FLASH Mandate)
- **Analysis:** Upgrading or patching Linux 4.4.60 requires recompiling `vmlinux`/`zImage` and writing the binary to NAND partition `rootfs` or `rootfs_1`.
- **Constraint:** The project operates under an absolute prohibition against writing to NAND or modifying kernel partitions without a verified non-UART recovery path.
- **Conclusion:** Kernel upgrades belong strictly to Track B (Community OpenWrt research on GitHub). Rejected for Track A.

---

### 2.13 OPT-USR-01: Standalone Userspace Modernization in `/data`
- **Classification:** **`HOLD`** (Viable Non-Destructive Pathway)
- **Analysis:** While the kernel cannot be touched, the persistent user partition `/data` (mounted read-write on NAND `mtd20`) allows executing self-contained, statically linked ARMv7 binaries.
- **Candidates:** Modern static Dropbear (with Ed25519 support), BoringTun Rust 0.7.1, static curl, and DoH proxy.
- **Constraint:** Must not overwrite vendor system files on SquashFS; must be launched via non-destructive hooks in `/data/auto_run.sh`.
- **Conclusion:** Approved for detailed design; individual components to be qualified sequentially.
