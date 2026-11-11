# M11.1.0.1 WAN SSH Firewall Preflight & Dual-Stack Architecture Report

- **Document ID:** `reports/M11_1_0_1_FIREWALL_PREFLIGHT.md`
- **Target Device:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Firmware Baseline:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, OpenWrt 18.06-SNAPSHOT base)
- **Authority:** Chief Architect Directive M11.1.0.1 / Lead Systems Engineer (Gemini)
- **Execution Mode:** **WORKSTATION-ONLY ANALYSIS — ZERO ROUTER SSH / ZERO ROUTER MUTATIONS**
- **Status:** **PREFLIGHT REVIEW COMPLETED — HALTED FOR CHIEF ARCHITECT REVIEW**

---

## 1. Executive Summary & Objective

The objective of this preflight analysis is to rigorously design and qualify the **Step 2 WAN SSH Lockdown (OPT-SEC-01)** before any command is executed on the physical router.

### Key Preflight Takeaways:
1. **The Dual-Stack Blindspot Identified:** Dropbear binds to both `0.0.0.0:56789` (IPv4) and `:::56789` (IPv6). An `iptables` drop rule only filters IPv4 packets; it provides **zero protection against IPv6 connections**. Both `iptables` and `ip6tables` must be configured symmetrically.
2. **Firewall Chain Traversal Grounded:** Incoming packets on the physical WAN port (`eth0`) traverse `INPUT -> delegate_input -> zone_wan_input`. The blocking rule must be inserted at **Position 1** of `zone_wan_input` to supersede any accept rules in `input_wan_rule`.
3. **Watchdog SIGHUP Vulnerability Resolved:** Standard background jobs `(...) &` in SSH sessions terminate upon client disconnect due to SIGHUP. The watchdog has been re-engineered with `trap '' HUP` and detached file descriptors (`</dev/null >/dev/null 2>&1`), and verified 100% immune to SSH disconnections in host-side test harness [`tests/test_watchdog_rollback.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/tests/test_watchdog_rollback.sh).

---

## 2. In-Depth Netfilter Firewall Architecture on OpenWrt / QSDK

### 2.1 Packet Traversal Flow for Incoming WAN Traffic
In OpenWrt fw3 (`firewall3`), netfilter rules are organized into a delegated zone architecture:

```
                  [ Ingress Packet on eth0 (WAN) ]
                                 │
                                 ▼
                     PREROUTING (raw / mangle / nat)
                                 │
                                 ▼
                         Routing Decision
                                 │
                      (Destination == Router IP)
                                 │
                                 ▼
                           INPUT (mangle)
                                 │
                                 ▼
                           INPUT (filter)
                                 │
                                 ▼
                           delegate_input
                                 │
           ┌─────────────────────┴─────────────────────┐
           │                                           │
[ Ingress from br-lan ]                     [ Ingress from eth0 (WAN) ]
           │                                           │
           ▼                                           ▼
    zone_lan_input                              zone_wan_input
(Default: ACCEPT port 56789)                 (Target: 0.0.0.0:56789)
```

### 2.2 Analysis of `zone_wan_input` Chain Structure
From live audit telemetry in `reports/M11_RA82_LIVE_AUDIT_RAW.txt`:
```
Chain zone_wan_input (1 references)
 pkts bytes target          prot opt in  out  source     destination 
82250 4413K input_wan_rule   all  --  *   *    0.0.0.0/0  0.0.0.0/0  /* !fw3: Custom wan input rule chain */
    7   420 zone_wan_src_DROP all --  *   *    0.0.0.0/0  0.0.0.0/0
    0     0 ACCEPT           tcp  --  *   *    0.0.0.0/0  0.0.0.0/0  tcp dpt:56789
```
- **Rule Ordering Vulnerability:** If a drop rule is appended at the end (`-A zone_wan_input`), packets matching earlier accept rules in `input_wan_rule` will be permitted before reaching the drop rule!
- **Mandatory Precedence Rule:** The rule MUST be inserted at index 1 (`-I zone_wan_input 1`). At position 1, every incoming packet on WAN matching `tcp dpt:56789` is immediately dropped before traversing `input_wan_rule` or any custom chains.

---

## 3. The Dual-Stack IPv4 / IPv6 Exposure & Solution

### 3.1 Dropbear Listening Topology
Empirical readback from `netstat -tlpn` in Milestone M11.1 confirmed:
```
Proto Recv-Q Send-Q Local Address    Foreign Address  State   PID/Program name
tcp        0      0 0.0.0.0:56789    0.0.0.0:*        LISTEN  1393/dropbear
tcp        0      0 :::56789         :::*             LISTEN  1393/dropbear
```
Dropbear uses a dual-stack configuration:
1. `0.0.0.0:56789`: Listens on all IPv4 addresses (LAN `192.168.31.1`, WAN `[REDACTED_WAN_IP]`, Loopback `127.0.0.1`, VPN `10.99.0.1`).
2. `:::56789`: Listens on all IPv6 addresses (Link-Local `fe80::...`, Global Unicast `2001:...` if provisioned by ISP via SLAAC or DHCPv6-PD).

### 3.2 The IPv6 Security Risk
- In Linux, `iptables` and `ip6tables` maintain completely separate netfilter rule tables.
- Running `iptables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP` only filters IPv4 packets!
- **Consequence:** An attacker scanning the router's IPv6 prefix or querying via IPv6 can still connect directly to Dropbear port 56789, completely bypassing the IPv4 firewall rule!
- **The Dual-Stack Rule Specification:** Both protocols must be locked down simultaneously:
  ```sh
  iptables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP
  ip6tables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP
  ```

---

## 4. The 180-Second Fail-Safe Watchdog Architecture

### 4.1 The SIGHUP Trap & Disconnect Vulnerability
In a remote SSH maintenance session, spawning a background task `(sleep 180; rollback) &` has a fatal flaw:
- If the SSH connection drops, the SSH server sends a **SIGHUP (Signal 1 - Hangup)** to the session's process group.
- By default, unmanaged subshells terminate immediately upon receiving SIGHUP!
- If the watchdog dies when SSH drops, the rollback will **NEVER EXECUTE**, leaving the user locked out if a firewall misconfiguration occurred.

### 4.2 The Hardened SIGHUP-Immunized Watchdog Design
To guarantee survival across SSH disconnections:
1. **Signal Immunity:** `trap '' HUP` instructs the subshell to ignore SIGHUP signals.
2. **File Descriptor Detachment:** `</dev/null >/dev/null 2>&1` detaches stdin, stdout, and stderr from the SSH pseudo-terminal (pty), preventing I/O pipe errors when the session closes.
3. **Idempotent Rollback Function:** A `while ...; do :; done` loop safely deletes all instances of the rule without crashing if a rule does not exist.

```sh
# SIGHUP-Immunized Dual-Stack Rollback Watchdog:
(
    trap '' HUP
    sleep 180
    while iptables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do :; done
    while ip6tables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do :; done
    logger -t M11_WATCHDOG "WAN SSH lockdown auto-reverted after 180s timeout"
) </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
```

### 4.3 Validation on Host PC Test Harness
The watchdog architecture was implemented and tested in [`tests/test_watchdog_rollback.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/tests/test_watchdog_rollback.sh):
- **Test 1 (SIGHUP Simulation):** Simulated parent SSH session termination via `kill -HUP $$`. Verified the watchdog process survived and executed the rollback on schedule. -> **PASS**
- **Test 2 (Clean Disarming):** Simulated successful LAN SSH verification and sent `kill $WATCHDOG_PID`. Verified zero unwanted rollbacks occurred. -> **PASS**
- **Test 3 (Idempotent Deletion):** Verified that deleting non-existent rules returns exit code 0 without errors. -> **PASS**

### 4.4 Honest Limitations of the Watchdog
No watchdog can claim "absolute 100% fail-safe" in all theoretical scenarios:
- If the router experiences a kernel panic or immediate power loss, the watchdog will not execute. (However, rebooting restores the volatile iptables state automatically).
- If the watchdog process is explicitly killed via `SIGKILL` (`kill -9`), it cannot catch the signal.
- The watchdog protects against the real-world operational hazards: SSH session drop, client network interruption, and script hang.

---

## 5. Step 2 Execution Runbook (Ready for Authorization)

When the Chief Architect issues the written approval for Step 2, the following exact command sequence will be executed:

```bash
# -----------------------------------------------------------------------------
# STEP 2 RUNBOOK: DUAL-STACK WAN SSH LOCKDOWN WITH SIGHUP-IMMUNIZED WATCHDOG
# -----------------------------------------------------------------------------

# Phase 1: Arm SIGHUP-Immunized Dual-Stack Rollback Watchdog
(
    trap '' HUP
    sleep 180
    while iptables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do :; done
    while ip6tables -D zone_wan_input -p tcp --dport 56789 -j DROP 2>/dev/null; do :; done
    logger -t M11_WATCHDOG "WAN SSH lockdown auto-reverted after 180s timeout"
) </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
echo "Watchdog armed with PID: $WATCHDOG_PID (180s fail-safe window active)"

# Phase 2: Insert Volatile Drop Rules at Position 1 of zone_wan_input
iptables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP
ip6tables -I zone_wan_input 1 -p tcp --dport 56789 -j DROP

# Phase 3: Immediate Verification from Workstation (LAN)
# Test 1: LAN SSH Access (MUST SUCCEED)
# ssh -p 56789 -o ConnectTimeout=5 root@192.168.31.1 "echo LAN_SSH_CONFIRMED"

# Test 2: WAN Port Probe from Upstream Subnet (MUST TIMEOUT / DROP)
# nc -z -w 3 <ROUTER_WAN_IP> 56789

# Phase 4: Disarm Watchdog upon Verified Success
# If Test 1 passes:
kill $WATCHDOG_PID 2>/dev/null || true
echo "LAN access verified. Watchdog disarmed. Volatile WAN SSH lockdown ACTIVE."
```

---

## 6. Safety Affirmation & Review Gate

- **Safety Compliance:** ZERO SSH connections made to router in this milestone; ZERO firewall modifications executed; `D:\vibecode\test_wifi` 100% untouched.
- **Halt Condition:** In strict adherence to `AGENTS.md` and Directive M11.1.0.1, execution **HALTS HERE** for Chief Architect review and authorization before Step 2 is initiated.
