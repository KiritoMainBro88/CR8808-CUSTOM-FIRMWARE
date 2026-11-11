# M11.1.0.2 Watchdog Hardening & Firewall Verification Audit Report

- **Document ID:** `reports/M11_1_0_2_WATCHDOG_FIREWALL_REPORT.md`
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Firmware Baseline:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit `armv7l`)
- **Authority Hierarchy:** ChatGPT (Chief Architect) / Gemini 3.8 Flash High (Lead Systems Engineer / Implementer)
- **Base Commit:** `3209e05` | **Branch:** `fix/m11-1-0-2-watchdog-hardening`
- **Execution Mode:** **100% WORKSTATION / PC-ONLY — ZERO ROUTER SSH — ZERO ROUTER MUTATIONS**
- **Status:** **M11_1_0_2_COMPLETE_HALTED_FOR_CHIEF_ARCHITECT_REVIEW**

---

## 1. Executive Summary & Directive Response

In response to Chief Architect Directive M11.1.0.2, the engineering team has completed a comprehensive hardening of all pre-trial mechanisms on the PC workstation without touching the physical router.

### Summary of Resolutions:

| Item | Chief Architect Finding | Engineering Solution & Empirical Validation | Status |
|---|---|---|---|
| **P0 Watchdog** | SIGHUP test only signaled parent; disarm wait was inadequate; missing TERM/failure tests | Created `scripts/watchdog_service.sh` with double-barrier protection; built 6-phase test suite `tests/test_watchdog_hardened.sh` validating direct SIGHUP, terminal hangup, full timeout expiry, dual-stack rollback, command errors, and disarm quiescence. Removed "100% reliability" claim. | **RESOLVED & PASS** |
| **P0 Rule Ownership** | Bulk deletion (`while iptables -D`) risked removing pre-existing rules | Implemented explicit ownership comments (`-m comment --comment "M11_1_TRIAL_SSH_BLOCK"`), prerequisite chain checks, and atomic failure handling. Tested in `tests/test_firewall_ownership.sh` against real Linux netfilter in WSL2; verified pre-existing rules are 100% preserved. | **RESOLVED & PASS** |
| **P0 IPv6 Reality** | Socket binding `:::56789` does not prove IPv6 routing, GUA address, or firewall state | Authored `docs/R0_FIREWALL_AUDIT_MANIFEST.md` and PC-side draft script `scripts/m11_1_firewall_investigation.sh` to measure GUA addresses, `::/0` routes, and `ip6tables` chains before any rule injection. Held behind authorization gate. | **RESOLVED & DESIGNED** |
| **P0 SSH Auth** | Dynamic `ssh-keyscan` is Trust-On-First-Use (TOFU) vulnerable to MitM | Pinned Dropbear RSA 2048-bit host key in `config/cr8818_host_key.pub` (`SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM`). Mandated fingerprint verification and out-of-band `known_hosts` synthesis in `docs/SSH_HOST_VERIFICATION.md`. | **RESOLVED & PINNED** |
| **P1 Sanitization** | Regex missed public IPv4, IPv6, and JSON serial fields | Built reusable sanitizer `scripts/sanitize_telemetry.sh`, test fixtures (`tests/fixtures/sanitizer_test_multiline.txt`, `sanitizer_test_json.json`), and test harness `tests/test_sanitizer.sh` proving 100% scrubbing of MACs, SSIDs, keys, serials, WAN/public IPv4, and IPv6. | **RESOLVED & PASS** |
| **Analytical Rigor** | Conflation of memory/network metrics | Rectified documentation: `SUnreclaim` decoupled from DMA buffers pending slab analysis; `NET_RX` softirqs decoupled from packet counts; socket bindings decoupled from Internet exposure; NSS match ratio isolated to IPv4 engine. | **RECTIFIED** |

---

## 2. In-Depth Technical Architecture & Verification

### 2.1 Watchdog Hardening & Double-Barrier Disarm

The hardened watchdog implementation in [`scripts/watchdog_service.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/watchdog_service.sh) resolves all failure modes identified during review:

```
[ Trial Rule Injected ] ──> Creates Sentinel Token (/tmp/m11_watchdog.armed)
                                     │
                                     ▼
                        [ Background Watchdog Subshell ]
                        - trap '' HUP (Immune to SSH drop)
                        - trap 'exit 0' TERM INT (Clean disarm)
                        - Detached FDs: </dev/null >/dev/null 2>&1
                        - sleep $TIMEOUT
                                     │
            ┌────────────────────────┴────────────────────────┐
            ▼                                                 ▼
[ Disarm Triggered Prior to Expiry ]        [ Timeout Reached Without Disarm ]
- Remove Sentinel File (/tmp/m11_watchdog.armed) - Check: Is Sentinel File Present?
- Send SIGTERM to Watchdog PID                    - YES: Execute IPv4 + IPv6 Rollback
- Result: Subshell exits cleanly;                 - Remove Sentinel File
          Zero firewall mutation                  - Log Event to Syslog
```

#### Verification Suite: `tests/test_watchdog_hardened.sh`
Executed inside WSL2 environment across 6 comprehensive phases:
1. **Direct SIGHUP Delivery:** Directly issued `kill -HUP $WATCHDOG_PID` to the running watchdog. The process trapped the signal, remained running, and subsequently executed the rollback upon timeout expiration. -> **PASS**
2. **Terminal Session Hangup:** Simulated SSH disconnect by spawning watchdog from a parent shell and killing the parent with `kill -HUP $$`. The orphaned watchdog process survived and executed scheduled rollback. -> **PASS**
3. **Full-Timeout Disarm Expiry:** Disarmed watchdog (sent SIGTERM and removed sentinel) with a 2.0s timeout, then waited for **3.5 seconds** (significantly exceeding the timeout window). Verified zero rollback actions occurred. -> **PASS**
4. **Dual-Stack Execution:** Verified that both IPv4 and IPv6 rollback commands are sequentially executed when timeout expires with active sentinel. -> **PASS**
5. **Command Failure Resilience:** Simulated an error in a rollback command (`exit 1`). Verified the watchdog did not crash or hang, but proceeded to execute subsequent rollback commands and terminated cleanly. -> **PASS**
6. **Double-Barrier Suppression:** Allowed watchdog to sleep for full timeout with sentinel absent. Verified rollback was safely suppressed. -> **PASS**

---

### 2.2 Firewall Rule Ownership & Transactional Rollback

The indiscriminate rule deletion pattern (`while iptables -D zone_wan_input -p tcp --dport 56789 -j DROP; do :; done`) has been **permanently eliminated**.

#### Rule Ownership Design:
1. **Explicit Comment Matching:** Every trial rule is tagged with `-m comment --comment "M11_1_TRIAL_SSH_BLOCK"`.
2. **Targeted Deletion:** Rollback explicitly specifies the comment tag:
   ```sh
   iptables -D zone_wan_input -p tcp --dport 56789 -m comment --comment "M11_1_TRIAL_SSH_BLOCK" -j DROP 2>/dev/null || true
   ip6tables -D zone_wan_input -p tcp --dport 56789 -m comment --comment "M11_1_TRIAL_SSH_BLOCK" -j DROP 2>/dev/null || true
   ```
3. **Atomic Transactional Rollback:**
   ```sh
   # Step 1: Pre-flight check chain existence
   iptables -L zone_wan_input -n >/dev/null 2>&1 || exit 1
   ip6tables -L zone_wan_input -n >/dev/null 2>&1 || exit 1

   # Step 2: Insert IPv4 rule
   iptables -I zone_wan_input 1 -p tcp --dport 56789 -m comment --comment "M11_1_TRIAL_SSH_BLOCK" -j DROP

   # Step 3: Insert IPv6 rule; if failure occurs, immediately rollback IPv4
   if ! ip6tables -I zone_wan_input 1 -p tcp --dport 56789 -m comment --comment "M11_1_TRIAL_SSH_BLOCK" -j DROP 2>/dev/null; then
       echo "[ERROR] IPv6 rule insertion failed! Reverting IPv4 rule atomically..."
       iptables -D zone_wan_input -p tcp --dport 56789 -m comment --comment "M11_1_TRIAL_SSH_BLOCK" -j DROP 2>/dev/null || true
       exit 1
   fi
   ```

#### Verification Suite: `tests/test_firewall_ownership.sh`
Executed against real netfilter chains in WSL2 (`sudo iptables` and `sudo ip6tables`):
- Injected pre-existing baseline rules (including an un-commented DROP on port 56789).
- Inserted tagged trial rule at position 1.
- Executed targeted rollback.
- **Empirical Confirmation:** The pre-existing un-commented DROP rule was **100% PRESERVED**, proving zero collateral damage to existing firewall state.
- Simulated IPv6 insertion failure: Verified that IPv4 was immediately and atomically reverted, leaving zero orphaned rules. -> **PASS**

---

### 2.3 Cryptographic SSH Host Key Pinning

Eliminated dynamic `ssh-keyscan` (TOFU vulnerability).

- **Pinned Host Key:** [`config/cr8818_host_key.pub`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/config/cr8818_host_key.pub)
- **Host Key Type:** RSA 2048-bit (`ssh-rsa`)
- **Pinned SHA-256 Fingerprint:** `SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM`
- **Specification:** [`docs/SSH_HOST_VERIFICATION.md`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/docs/SSH_HOST_VERIFICATION.md)
- **Protocol:** All future SSH invocations verify local public key integrity against the expected SHA-256 fingerprint, synthesize a dedicated `UserKnownHostsFile` locally, and connect with `StrictHostKeyChecking=yes`. Any MitM or key change results in immediate connection termination before credentials are exchanged.

---

### 2.4 Sanitization Test Suite & Privacy Protection

Built an automated, multi-pattern redaction engine in [`scripts/sanitize_telemetry.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/sanitize_telemetry.sh) and verified it via [`tests/test_sanitizer.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/tests/test_sanitizer.sh).

#### Verified Scrubbing Capabilities across Multiline Text & JSON:
- **Serial Numbers:** `Serial : 35123/240019283`, `"serial": "..."`, `"sn": "..."` $\rightarrow$ `[REDACTED_SERIAL]`
- **MAC Addresses:** Colon (`E4:39:DF:04:6C:FD`) and hyphen (`E4-39-DF-04-6C-FE`) formats $\rightarrow$ `[REDACTED_MAC]`
- **Wi-Fi SSIDs:** `ESSID:"..."`, `ssid='...'`, `"ssid": "..."` $\rightarrow$ `[REDACTED_SSID]`
- **Wi-Fi PSK & WPA3 Passwords:** `key='...'`, `sae_password='...'`, `"key": "..."` $\rightarrow$ `[REDACTED_WIFI_KEY]`
- **WireGuard Keys:** `-srvkey ...`, `-clientkey ...`, `private-key ...`, `"srvkey": "..."` $\rightarrow$ `[REDACTED_WG_KEY]`
- **WAN & Public IPv4:** `192.168.100.x` $\rightarrow$ `[REDACTED_WAN_IP]`; Public IPs (`118.68.x.x`) $\rightarrow$ `[REDACTED_PUBLIC_IP]`
- **IPv6 Addresses:** Global Unicast (`2402:...`), Link-Local (`fe80:...`), ULA (`fd00:...`) $\rightarrow$ `[REDACTED_IPV6_*]`
- **Test Result:** 30/30 assertions PASSED with zero leaks across text and JSON fixtures.

---

### 2.5 Class R0 Firewall Read-Only Investigation Manifest

To rigorously resolve the questions regarding IPv6 Global Unicast routing and netfilter chain layout before executing any firewall mutation, the team prepared:
- **Manifest:** [`docs/R0_FIREWALL_AUDIT_MANIFEST.md`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/docs/R0_FIREWALL_AUDIT_MANIFEST.md)
- **Script:** [`scripts/m11_1_firewall_investigation.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/m11_1_firewall_investigation.sh)

> [!IMPORTANT]
> **GATE LOCK CONFIRMED:** The script incorporates a mandatory pre-flight gate (`AUTHORIZE_R0_FIREWALL_EXECUTION=1`). Executing it without explicit authorization aborts immediately with exit code 1. **Zero SSH connections were opened to the router.**

---

### 2.6 Rectification of Technical Statements

In compliance with Directive M11.1.0.2 G, technical statements across reports have been updated:
1. **`SUnreclaim` Nuance:** Decoupled from physical DMA ring buffers. Clarified that `SUnreclaim` (56.8 MB) represents unevictable kernel slab caches (which include dentry, inode, skbuff heads, and driver structures); exact breakdown requires slabinfo analysis.
2. **`NET_RX` SoftIRQ Events:** Clarified that softirq event counters reflect scheduler servicing cycles and NAPI polling loops, not an exact 1:1 packet count (due to NAPI batching).
3. **Socket Binding vs Exposure:** Clarified that Dropbear listening on `0.0.0.0` and `:::` does not constitute direct Internet exposure without verifying external routing and firewall filtering.
4. **NSS Rule Match Ratio:** Clarified that the 96.96% ratio is strictly internal to the IPv4 NSS acceleration engine, not a global router offload ratio.

---

## 3. Verification & Artifacts Summary

### 3.1 Test Suite Summary
All test suites executed inside WSL2 and passed cleanly:
- `tests/test_watchdog_hardened.sh`: 6/6 test phases PASSED.
- `tests/test_firewall_ownership.sh`: 5/5 test phases PASSED.
- `tests/test_sanitizer.sh`: 30/30 assertions PASSED.
- `tests/test_inmemory_delta.sh`: In-memory AWK delta stream PASSED.

### 3.2 SHA-256 Checksums of New & Modified Deliverables

```
7249b6574f88e1781283624e75877f6b92a2c1ca9d2cfc7a0d4cbb8ad097463f  scripts/watchdog_service.sh
1e36f45a05b38a4d46781fbfba3a5a75d5062c3e5bf06fc0c9c7e090df32cf39  scripts/sanitize_telemetry.sh
e56bc444760a92d2449557f6b47c4e51ebbb39d481f37e4be6561cf02a3a5e80  scripts/m11_1_firewall_investigation.sh
72ce346c48d2451bebbd25c4ef9b4cb0e980e1a8bb232d3f3f044bb7f54c2ea2  tests/test_watchdog_hardened.sh
a3a1f94b1a8d052d92131efcfc85772390f7a77d85ea150c9962a98f1aa2de0c  tests/test_firewall_ownership.sh
f5c40465a3952ba85002ba5ebf272a74c1eb6064f2beea023ffbf3f568a0d922  tests/test_sanitizer.sh
501fe2314bc217d7bbf115c5e0e0e01479262f2f116773950ff49156c7c25227  docs/SSH_HOST_VERIFICATION.md
0562e84d431c34a6ef2f6f3630f5c1d68019fb0bebe567a5b3a4a984400dcfe8  docs/R0_FIREWALL_AUDIT_MANIFEST.md
81fb771dfec1b28d05541e7f6ea49a9446d6540c749ef554a935fa7bf1e2f497  config/cr8818_host_key.pub
```

### 3.3 Git Governance & Safety Confirmation
- **Target Branch:** `fix/m11-1-0-2-watchdog-hardening`
- **Merge Base:** `3209e05` (Zero commits overwritten, zero force-pushes).
- **Physical Router Safety:** ZERO SSH connections opened, ZERO firewall edits, ZERO UCI/NVRAM writes, ZERO flash commands, ZERO reboots.
- **Lab Directory Integrity:** `D:\vibecode\test_wifi` remains 100% pristine and untouched.

---

## 4. Status Transition & Next Step Recommendation

The team recommends:
1. **Acceptance of Milestone M11.1.0.2:** Formally approve the watchdog, rule ownership, pinned SSH authentication, and sanitizer deliverables.
2. **Authorization of Step 1.5 (Class R0 Firewall Investigation):** Prior to injecting firewall rules on the router, authorize execution of [`scripts/m11_1_firewall_investigation.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/m11_1_firewall_investigation.sh) (`AUTHORIZE_R0_FIREWALL_EXECUTION=1`) to empirically confirm IPv6 GUA routes and `ip6tables` chain names on the physical router.
3. **Step 2 (WAN SSH Lockdown Gate):** Execute Step 2 only after the empirical firewall investigation confirms chain availability.

Execution is currently **STRICTLY HALTED** awaiting Chief Architect review and written directive.
