# MILESTONE M11.1: ARCHITECTURE-SANCTIONED TRIAL PLAN & EXPERIMENTAL CONTROLS

**Document ID:** `CR8808-M11.1-TRIAL-PLAN-001`  
**Milestone:** `M11.1 – Controlled Runtime Trials & Experimental Validation`  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Linux 4.4.60 QSDK)  
**Reporting Authority:** Gemini 3.8 Flash High – Lead Developer / Research Engineer  
**Sanctioning Authority:** ChatGPT – Chief Architect / Architecture Lead  
**Date:** November 11, 2026  
**Safety Protocol:** `STRICT NO-GO FLASH` (Zero router writes, 0 flashing, 0 NAND/NVRAM modifications, 0 reboots)  
**Reference Specification:** [`docs/09_WIREGUARD_RUST_PLAN.md`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/docs/09_WIREGUARD_RUST_PLAN.md)

---

## 1. Executive Summary & Proposal Disposition Matrix

Following the Chief Architect's formal technical audit of Milestone M11, all 8 proposed optimizations have been systematically categorized into three binding operational dispositions:
- **`GO (Priority Security Action)`:** Approved for controlled execution following verified runbook.
- **`HOLD (Research & Isolated Benchmarking Only)`:** Deferred pending empirical delta measurements; no production changes permitted.
- **`REJECT (Dismissed as Unwarranted)`:** Formally rejected due to technical or mathematical invalidity.

```
+----------------------------------------------------------------------------------------------------+
|                                    MASTER PROPOSAL DISPOSITION MATRIX                              |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| ID  | Proposal Title        | Target Subsystem    | Disposition       | Architecture Lead Directive|
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 6.1 | Restrict WAN SSH      | Firewall / Dropbear | **GO (PRIORITY)** | Security priority. Verify  |
|     |                       |                     |                   | LAN access & rollback first|
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 1.1 | Enable RPS for wg0/lan| Linux Network Queue | **HOLD**          | Measure CPU deltas first;  |
|     |                       |                     |                   | test as isolated trial.    |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 3.1 | BoringTun Rust Deploy | WireGuard Subsystem | **HOLD**          | Keep Go running; execute   |
|     |                       |                     | (ISOLATED TRIAL)  | separate sandbox trial.    |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 2.1 | Stop Vendor Daemons   | Xiaomi Background   | **HOLD**          | Measure true RssAnon first;|
|     |                       | Daemons             |                   | do not stop blindly.       |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 4.1 | Enable UL-OFDMA       | 5 GHz Wi-Fi Driver  | **HOLD**          | Verify QCA driver support; |
|     |                       |                     |                   | requires A/B test.         |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 4.2 | Enable 802.11k/v      | UCI Wireless Config | **HOLD**          | Verify client compatibility|
|     |                       |                     |                   | and driver handling.       |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 5.1 | Conntrack Timeouts    | Netfilter Sysctl    | **REJECT**        | Load is 3.37% (552/16384). |
|     |                       |                     |                   | No pressure exists.        |
+-----+-----------------------+---------------------+-------------------+----------------------------+
| 5.2 | TCP Buffer Ceiling    | Core Network Sysctl | **REJECT**        | BDP @ 1Gbps/20ms is 2.5MB; |
|     |                       |                     |                   | buffers are not prealloc.  |
+-----+-----------------------+---------------------+-------------------+----------------------------+
```

---

## 2. Execution Plan: Proposal 6.1 – WAN SSH Hardening (`GO`)

### 2.1 Environmental Ground Truth & Context
- **WAN Interface:** `eth0` with IP address `[REDACTED_WAN_IP]/24`.
- **Topological Reality:** The router is located in a double-NAT topology behind an upstream ISP ONT/gateway (`[REDACTED_WAN_GW]`).
- **Exposure Analysis:** Dropbear port `56789` is open to the `[REDACTED_WAN_SUBNET]` subnet. It is NOT directly reachable from the public Internet unless the upstream ONT has port forwarding configured. The packet counter (7 packets) confirms minimal traffic, with no evidence of successful unauthorized login.
- **Security Mandate:** Even on private subnets, exposing management SSH with password authentication violates zero-trust principles.

### 2.2 Controlled Hardening Runbook:
1. **Pre-flight Check:** Establish an independent, active SSH session from a LAN client (`192.168.31.x`) to verify LAN connectivity before touching WAN rules.
2. **Runtime Rule Adjustment:**
   Remove the wildcard WAN ACCEPT rule:
   ```sh
   iptables -D zone_wan_input -p tcp --dport 56789 -j ACCEPT
   ```
   Or restrict it exclusively to the known management subnet (`[REDACTED_WAN_SUBNET]`):
   ```sh
   iptables -I zone_wan_input 3 -p tcp -s <MANAGEMENT_WAN_SUBNET> --dport 56789 -j ACCEPT
   ```
3. **Verification:** Confirm connection is blocked from outside WAN and remains 100% accessible from `192.168.31.1:56789`.
4. **Instant Rollback:**
   ```sh
   iptables -I zone_wan_input 3 -p tcp --dport 56789 -j ACCEPT
   ```

---

## 3. Isolated Sandbox Trial Plan: Proposal 3.1 – BoringTun Rust (`HOLD`)

In strict accordance with [`docs/09_WIREGUARD_RUST_PLAN.md`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/docs/09_WIREGUARD_RUST_PLAN.md):
- **PROHIBITION:** The active WireGuard Go daemon (`/data/wg_server`) on `wg0` (`10.99.0.1:51820`) **MUST NOT BE STOPPED OR ALTERED**.
- **ISOLATED TRIAL SCOPE:** BoringTun Rust will be evaluated exclusively on an independent sandbox port (`51821 UDP`) and dedicated sandbox interface (`wg1`), ensuring zero impact on live VPN connectivity.

### 3.1 Step-by-Step Validation Sequence:
```
+----------------------------------------------------------------------------------------------------+
|                                    BORINGTUN ISOLATED VALIDATION GATES                             |
+--------+--------------------------+----------------------------------------------------------------+
| Gate   | Requirement              | Verification Protocol                                          |
+--------+--------------------------+----------------------------------------------------------------+
| Gate 1 | Sandbox Interface Creation| Create isolated TUN interface `wg1` via `boringtun-cli-armv7`  |
|        |                          | on test port `51821 UDP`. Production `wg0` remains untouched.  |
+--------+--------------------------+----------------------------------------------------------------+
| Gate 2 | Key Handshake & Ping     | Perform handshake with test client (`10.99.1.2`); verify 0-loss|
|        |                          | ICMP echo replies over `wg1`.                                  |
+--------+--------------------------+----------------------------------------------------------------+
| Gate 3 | Memory Accounting (RSS)  | Measure exact `RssAnon` and `VmRSS` from `/proc/<PID>/status`; |
|        |                          | compare against `wg_server` Go process baseline.               |
+--------+--------------------------+----------------------------------------------------------------+
| Gate 4 | Throughput & Jitter      | Run 60-second iperf3 TCP and UDP throughput and ping jitter.   |
+--------+--------------------------+----------------------------------------------------------------+
| Gate 5 | Clean Teardown           | Kill BoringTun test instance; destroy `wg1`; verify zero       |
|        |                          | residual kernel resources.                                     |
+--------+--------------------------+----------------------------------------------------------------+
```

---

## 4. Controlled CPU Delta Trial Plan: Proposal 1.1 – RPS (`HOLD`)

- **Current State:** RPS is disabled (`rps_cpus: 0`).
- **Hypothesis:** Steering softirq processing for software-bound interfaces (`wg0`, `br-lan`) to CPU1 will reduce packet processing jitter on CPU0.
- **Prerequisite:** Baseline CPU utilization and softirq rate must be measured using `scripts/measure_cpu_deltas.sh` during a 30-second idle period and a 30-second iperf3 network load.
- **Trial Scope:** If and only if baseline measurement proves CPU0 exceeds 70% softirq load while CPU1 remains below 10%, a single-variable trial will be authorized:
  ```sh
  echo 2 > /sys/class/net/wg0/queues/rx-0/rps_cpus
  ```
  Followed immediately by repeat benchmark and mandatory comparison of packet reordering and ping jitter.

---

## 5. Summary of Prohibitions for Milestone M11.1

1. **NO Flash / NAND Writes:** Flash memory remains strictly read-only.
2. **NO NVRAM Commits:** No `nvram set` or `nvram commit` commands.
3. **NO Reboots:** Router remains in active uptime.
4. **NO Blind Daemon Termination:** Vendor services (`messagingagent`, etc.) remain running.
5. **NO Production WireGuard Disruption:** `/data/wg_server` remains running on `wg0`.
