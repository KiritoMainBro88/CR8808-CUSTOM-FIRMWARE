# Project Backlog

Status values: `READY`, `IN_PROGRESS`, `BLOCKED`, `DONE`, `NOT_STARTED`.

| ID | Task | Phase | Status | Owner | Dependency |
|---|---|---|---|---|---|
| P0-001 | Read project instructions and initialize Git safely | P0 | DONE | Gemini | None |
| P0-002 | Create project directory tree | P0 | DONE | Gemini | P0-001 |
| P1-001 | Audit PC/Windows/WSL2 resources without installing tools | P1 | DONE | Gemini | P0-002 |
| P1-002 | Audit upstream repositories, licenses, branches and commits | P1 | DONE | Gemini | P0-002 |
| P1-003 | Inspect CR881x/CR8808 target, DTS, switch and NSS source support | P1 | DONE | Gemini | P1-002 |
| P1-004 | Produce source/hardware compatibility report | P1 | DONE | Gemini | P1-001..003 |
| P1-GH | GitHub repository integration, security audit and remote push | P1 | DONE | Gemini | P1-004 |
| P1-REV | ChatGPT Architecture Review response & technical corrections | P1 | DONE | Gemini | P1-GH |
| P1-G1F | Gate G1 architecture finalization, parity matrix & design specs | P1 | DONE | Gemini | P1-REV |
| P1-REV2 | Gate G1 Round 2 corrections (PHY/Switch, DSA, Parity, Recovery, R0) | P1 | DONE | Gemini | P1-G1F |
| P1-REV3 | Gate G1 Round 3 corrections (Port mapping, SGMII, GPIO39, Architecture) | P1 | DONE | Gemini | P1-REV2 |
| P1-REV4 | Gate G1 Round 4 corrections (DSA vs NSS resolution, GPIO39 analysis, Calibration) | P1 | DONE | Gemini | P1-REV3 |
| P1-REV5 | Gate G1 Round 5 corrections (Upstream 6.18 vs 6.19, 3-way NSS, Calibration, CR8806) | P1 | DONE | Gemini | P1-REV4 |
| P1-REV5.1 | Gate G1 Round 5.1 corrections (yangfl audit, SerDes patch 940, caldata fix, governance) | P1 | DONE | Gemini | P1-REV5 |
| P1-REV5.2 | Gate G1 Round 5.2 corrections (Exact cal paths, AHB bus, PCIe audit, Kuncy/zcop, NAND) | P1 | DONE | Gemini | P1-REV5.1 |
| P2-NSS-RES | Qualcomm NSS Hardware Offload Porting Research (Phase A Source Audit & Phase B Feasibility) | P2 | DONE | Gemini | P1-REV5.2 |
| P2-NSS-POC-M1-M2 | NSS + YT9215SC PC Prototype: M1 Source Lock & M2 Tag Adapter Compile & Test | P2 | DONE | Gemini | P2-NSS-RES |
| P2-NSS-POC-M3 | NSS + YT9215SC PC Prototype: M3 Independent Oracle Tests, Kernel Patch Validation & DTS Audit | P2 | DONE | Gemini | P2-NSS-POC-M1-M2 |
| P2-NSS-POC-M4 | NSS + YT9215SC PC Prototype: M4 Kernel Kbuild Audit, Option A/B Separation & Register Control | P2 | DONE | Gemini | P2-NSS-POC-M3 |
| P2-NSS-POC-M5 | NSS + YT9215SC PC Prototype: M5 OpenWrt Buildroot Firmware Image Build & Package Linking | P2 | BLOCKED | ChatGPT + User | M4 Architecture Review Approval |
| P1-CLN | Git history cleanup application (Option 1 force-push) | P1 | BLOCKED | Product Owner | P1-REV5.2 dry-run approval |
| P2-001 | Re-audit router baseline using approved Class R0 read-only commands | P2 | BLOCKED | Gemini | R0 Manifest approval |
| P2-002 | Finalize feature parity inventory against on-device baseline | P2 | NOT_STARTED | Gemini | P2-001 |
| P2-003 | Select base and integration strategy | P2 | IN_PROGRESS | ChatGPT + User | Architecture Proposal under review |
| P3-001 | Implement approved clean DSA target and YT9215 driver changes | P3 | NOT_STARTED | Gemini | P2-003, P1-CLN |
| P3-RUST-STRAT | Architecture Directive: Rust-First Userspace Strategy & BoringTun Evaluation | P3 | DONE | Gemini | P2-NSS-POC-M4 |
| P3-002 | Integrate Rust BoringTun package and procd service | P3 | DONE | Gemini | P3-RUST-STRAT |
| P4-VISION-HARDENING | Modern Firmware Vision, Parity Gate, Security Strategy & BoringTun Integration Tests | P4 | DONE | Gemini | P3-002 |
| P4-001 | Milestone M5A Packaging Skeleton Verification (NON_FLASHABLE_TEST_ARTIFACT) | P4 | DONE | Gemini | P4-VISION-HARDENING |
| P5-M6 | Milestone M6 Full OpenWrt 25.12.6 Source Build, BoringTun Issue #498 & #495 Verification | P5 | DONE | Gemini | P4-001 |
| P5-M6-REV | ChatGPT Architecture Lead Review & Acceptance of Milestone M6 | P5 | DONE | ChatGPT + User | P5-M6 |
| P6-M7.0 | Milestone M7.0 Multi-Repository Architecture & Technology Selection | P6 | DONE | Gemini | P5-M6-REV |
| P6-M7.0-REV | ChatGPT Architecture Lead Review & Selection Sign-Off for Milestone M7.0 | P6 | DONE | ChatGPT + User | P6-M7.0 |
| P6-M7.1 | Milestone M7.1 Chinese Community Research & Hardware Evidence Reconciliation | P6 | DONE | Gemini | P6-M7.0-REV |
| P6-M7.1-REV | ChatGPT Architecture Lead Review of Milestone M7.1 (Requested Revision 1) | P6 | DONE | ChatGPT + User | P6-M7.1 |
| P6-M7.1-REV1 | Milestone M7.1 Revision 1 Evidence Corrections & Technical Reconciliation | P6 | DONE | Gemini | P6-M7.1-REV |
| P6-M7.1-REV1-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1 |
| P6-M7.1-REV1.1 | Milestone M7.1 Revision 1.1 Final Evidence Reconciliation | P6 | DONE | Gemini | P6-M7.1-REV1-SIGN |
| P6-M7.1-REV1.1-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1.1 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1.1 |
| P6-M7.1-REV1.2 | Milestone M7.1 Revision 1.2 Final Evidence Audit & ADR Ratification | P6 | DONE | Gemini | P6-M7.1-REV1.1-SIGN |
| P6-M7.1-REV1.2-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1.2 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1.2 |
| P7-M8-PREFLIGHT | Milestone M8.0 Pre-Flight Verification Gate (YT9215 6.12 backport specification, Kbuild verification) | P7 | DONE | Gemini | P6-M7.1-REV1.2-SIGN |
| P7-M8-ROADMAP | Kernel Lifecycle & Migration Roadmap (6.12 LTS Dec 2026 -> 6.18 LTS Dec 2027) | P7 | DONE | Gemini | P7-M8-PREFLIGHT |
| P7-M8-TRACK-A-BUILD | Milestone M8.1 Track A Firmware Image Build (OpenWrt 25.12.6, Linux 6.12.112, factory.ubi & sysupgrade.bin) | P7 | DONE | Gemini | P7-M8-ROADMAP |
| P8-M9-IMAGE-VALIDATION | Milestone M9 Image Validation, FIT Inspection, UBI Partition Audit & Recovery Strategy | P8 | DONE | Gemini | P7-M8-TRACK-A-BUILD |
| P9-M10-HARDWARE-ENABLEMENT | Milestone M10 Hardware Enablement (Wi-Fi DTS, Remoteproc SMEM 507, BDF, Caldata, Switch Reset Timing, RAM Budget & Recovery Feasibility) | P9 | DONE | Gemini | P8-M9-IMAGE-VALIDATION |
| P9-M10-REV | ChatGPT Architecture Review of Milestone M10 (Conditional Acceptance & 5 P0 Queries issued) | P9 | DONE | ChatGPT + User | P9-M10-HARDWARE-ENABLEMENT |
| P9-M10.1-EVIDENCE-CORRECTIONS | Milestone M10.1 Evidence Corrections & Architecture Review (Q6 UserPD 2 proof, GPIO 39 RESETB audit, RAM decomposition, Recovery disambiguation, DTB extraction) | P9 | DONE | Gemini | P9-M10-REV |
| P9-M10.1-REV-SIGN | ChatGPT Chief Architect Sign-Off of M10.1 & Directive for Milestone M10.2 Non-UART Deployment | P9 | DONE | ChatGPT + User | P9-M10.1-EVIDENCE-CORRECTIONS |
| P9-M10.2-KEXEC-AUDIT | Milestone M10.2 Non-UART Safe Deployment & KEXEC Feasibility (KEXEC audit, ARM32/ARM64 barrier proof, Boot chain & Dual-slot failover analysis) | P9 | DONE | Gemini | P9-M10.1-REV-SIGN |
| P9-M10.2-REV | ChatGPT Chief Architect Review of M10.2 (Identified 4 critical flaws: Slot inversion, partition map, unverified recovery, KEXEC reframing) | P9 | DONE | ChatGPT + User | P9-M10.2-KEXEC-AUDIT |
| P9-M10.2.1-EVIDENCE-CORRECTIONS | Milestone M10.2.1 Critical Evidence Correction & Non-UART Recovery Validation (Live SSH readback, slot correction, partition verification, recovery reclassification) | P9 | DONE | Gemini | P9-M10.2-REV |
| P9-M10.2.1-REV | ChatGPT Chief Architect Review & Direction: Pivot to Dual-Track Strategy (Track A RA82 Primary, Track B OpenWrt Community) | P9 | DONE | ChatGPT + User | P9-M10.2.1-EVIDENCE-CORRECTIONS |
| P10-M11-RA82-AUDIT | Milestone M11 RA82 Performance & Security Optimization Audit (Live baseline, NSS offload audit, CPU IRQ imbalance, Wi-Fi HE160, BoringTun Rust, Security exposure, 8 Proposals Roadmap) | P10 | DONE | Gemini | P9-M10.2.1-REV |
| P10-M11-REV | ChatGPT Chief Architect Review of M11 (Caught P0 credential exposure & 6 analytical flaws: NSS, CPU, RAM, VPN, Conntrack, Wi-Fi) | P10 | DONE | ChatGPT + User | P10-M11-RA82-AUDIT |
| P10-M11.0.1-CONTAINMENT | Milestone M11.0.1 Security Incident Containment & Evidence Correction (Redaction, gitignore, script hardening, NSS semantics, CPU delta method, RAM accounting, Trial Plan) | P10 | DONE | Gemini | P10-M11-REV |
| P10-M11.0.1-REV | ChatGPT Chief Architect Review of M11.0.1 Security Containment & Evidence Correction | P10 | DONE | ChatGPT + User | P10-M11.0.1-CONTAINMENT |
| P10-M11.0.2-PREFLIGHT | Milestone M11.0.2 RA82 Optimization Readiness & Safe Trial Preflight (Task A-E audit, matrix, test fixtures, preflight runbooks) | P10 | DONE | Gemini | P10-M11.0.1-REV |
| P10-M11.0.2-REV | ChatGPT Chief Architect Review of M11.0.2 Preflight & Optimization Matrix | P10 | DONE | ChatGPT + User | P10-M11.0.2-PREFLIGHT |
| P10-M11.1-TRIAL | Milestone M11.1 Controlled Runtime Reversible Trials (Step 1 R0 Baseline DONE; Step 2 WAN SSH READY) | P10 | DONE | Gemini | P10-M11.0.2-REV |
| P10-M11.1.0.1-CORRECTIONS | Milestone M11.1.0.1 Evidence Correction & WAN SSH Firewall Preflight | P10 | DONE | Gemini | P10-M11.1-TRIAL |
| P10-M11.1.0.2-WATCHDOG | Milestone M11.1.0.2 Watchdog Hardening, Rule Ownership & Firewall Verification | P10 | DONE | Gemini | P10-M11.1.0.1-CORRECTIONS |
| P10-M11.1.0.3-INTEGRITY | Milestone M11.1.0.3 Preflight Integrity & Safety Corrections | P10 | DONE | Gemini | P10-M11.1.0.2-WATCHDOG |
| P10-M11.1.0.4-SAFETY | Milestone M11.1.0.4 Critical Safety Corrections & Preflight Verification | P10 | DONE | Gemini | P10-M11.1.0.3-INTEGRITY |
| P10-M11.1.0.5-TRANSACTIONAL | Milestone M11.1.0.5 Transactional Firewall Recovery & Complete IPv6 Sanitization | P10 | DONE | Gemini | P10-M11.1.0.4-SAFETY |
| P10-M11.1-STEP1.5-FW-AUDIT | Milestone M11.1 Step 1.5 Class R0 Firewall & IPv6 Investigation (scripts/m11_1_r0_minimal_audit.sh) | P10 | DONE | Gemini | P10-M11.1.0.5-TRANSACTIONAL |
| P10-M11.1-STEP2-SSH | Milestone M11.1 Step 2 WAN SSH Dropbear Lockdown (Dual-stack + Hardened Watchdog) | P10 | BLOCKED | ChatGPT + User | M11.1 Step 1.5 Verification |
| P10-M11.2-PERSISTENCE | Milestone M11.2 RA82 Enhancement Integration & Hardening (/data/auto_run.sh persistence) | P10 | NOT_STARTED | Gemini | P10-M11.1-STEP2-SSH |
| P10-M12-COMMUNITY-OPENWRT | Track B: Community OpenWrt R&D Maintenance & Upstream Coordination on GitHub | P10 | NOT_STARTED | Gemini | P10-M11.0.2-REV |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M11.1 Step 1.5 Class R0 Firewall Audit & Safety Closure completed on branch `fix/m11-1-step1-5-r0-audit-and-safety-closure`:
1. **Authorized Minimal R0 Read-Only Live Audit (Part A):** Executed `scripts/m11_1_r0_minimal_audit.sh` over LAN management interface (`192.168.31.1:56789`) via in-memory stdin pipe (0 files created on router, 0 config writes). Captured live interfaces, routes, iptables/ip6tables filter tables, Dropbear sockets, and TCP sockets. Confirmed 0/9 section failures (COMPLETE). Confidential raw output preserved in `local_raw_audit/m11_1_r0_minimal_raw.txt` (mode 600, .gitignored); published sanitized report to `reports/M11_1_R0_MINIMAL_AUDIT_SANITIZED.txt`.
2. **WAN SSH Exposure Findings:**
   - **IPv4:** HIGH RISK. Explicit rule `Allow-WAN-SSH` in `zone_wan_input` accepting port 56789 from WAN (active counter: 10 pkts, 504 bytes), with Dropbear root password auth enabled.
   - **IPv6:** CRITICAL RISK. `ip6tables` has ZERO rules, ZERO zone chains (`zone_wan_input` does not exist), and default policy `ACCEPT` on `INPUT`. Dropbear is listening on `:::56789`, completely exposed to the global IPv6 Internet.
3. **Safety Corrections Closed on PC (Part B):**
   - **Watchdog:** Forced emergency rollback on transition lock contention timeout; immediate emergency rollback upon unexpected `SIGTERM`/`SIGINT` while `ARMED`. Validated via `tests/test_watchdog_hardened.sh` (12/12 PASS).
   - **Firewall Manager:** Decoupled independent IPv4 and IPv6 rollback (missing IPv6 chain never blocks IPv4 rollback); exact comment ownership regex matching. Validated via `tests/test_firewall_ownership.sh` (11/11 PASS).
   - **Investigation Pipeline:** Strict non-zero exit codes on partial/failed audits; previous report retention. Validated via `tests/test_firewall_investigation_mock.sh` (8/8 PASS).
   - Total automated test assertions: 130/130 PASS (100% pass rate).
4. **Deliverables & Strict Safety Boundary:** Authored `reports/M11_1_STEP1_5_R0_AUDIT_REPORT.md`. Workstation execution with authorized read-only SSH readback (ZERO firewall edits, ZERO writes to router, ZERO reboots). Lab directory `D:\vibecode\test_wifi` 100% untouched. Status: `M11_1_STEP1_5_R0_AUDIT_COMPLETED_AWAITING_REVIEW`. Author: Gemini (Lead Systems Engineer).
