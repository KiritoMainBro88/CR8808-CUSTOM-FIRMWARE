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
| P10-M11.1.1-POST-AUDIT-REMEDIATION | Milestone M11.1.1 Post-Audit Security Remediation & Runtime Readiness (Sanitizer EUI-64 fix, Watchdog ACQ=1 & sleep rollback, Firewall dual-stack rebuild, Exposure reconciliation, Host key sync, BoringTun preflight) | P10 | DONE | Gemini | P10-M11.1-STEP1.5-FW-AUDIT |
| P10-M12-PERFORMANCE-MODERNIZATION | Milestone M12 RA82 Performance Engineering & Modernization Program (In-memory audit, Top 5 bottlenecks, 7-module tuning framework, BoringTun Rust ARMv7, wg1 isolated testbed, 5-benchmark suite) | P10 | DONE | Gemini | P10-M11.1.1-POST-AUDIT-REMEDIATION |
| P10-M12-P0-OUTAGE-INVESTIGATION | Milestone M12 P0 Network Outage Investigation & Root Cause Analysis (Reconstructed timeline, ruled out agent/OOM/kernel crash, verified hardware reboot at 19:15:30 with flag_boot_type=2, diagnosed PC UDP port exhaustion Event 4266) | P10 | DONE | Gemini | P10-M12-PERFORMANCE-MODERNIZATION |
| P10-M12-PC-ENHANCEMENT | Milestone M12 PC-Side Optimization & WireGuard Simulation (105/105 framework tests pass, DNS stability profile, BoringTun PC dual-namespace simulation 244 Mbps with 0 leak) | P10 | DONE | Gemini | P10-M12-P0-OUTAGE-INVESTIGATION |
| P10-M12-REV | ChatGPT Chief Architect Review & Direction for Milestone M12 Performance Engineering & Outage RCA | P10 | IN_PROGRESS | ChatGPT + User | P10-M12-PC-ENHANCEMENT |
| P10-M12.4-CONTROLLED-TRIALS | Milestone M12.4 Controlled Runtime Reversible Trials (Single-profile opt & wg1 BoringTun trial upon authorization) | P10 | BLOCKED | ChatGPT + User | P10-M12-REV |
| P10-M11.1-STEP2-SSH | Milestone M11.1 Step 2 WAN SSH Dropbear Lockdown (Dual-stack + Hardened Watchdog) | P10 | BLOCKED | ChatGPT + User | M11.1.1 Remediation Verification |
| P10-M11.2-PERSISTENCE | Milestone M11.2 RA82 Enhancement Integration & Hardening (/data/auto_run.sh persistence) | P10 | NOT_STARTED | Gemini | P10-M11.1-STEP2-SSH |
| P10-M12-COMMUNITY-OPENWRT | Track B: Community OpenWrt R&D Maintenance & Upstream Coordination on GitHub | P10 | NOT_STARTED | Gemini | P10-M11.0.2-REV |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M12 Performance Engineering, P0 Outage Investigation & PC Modernization completed on branch `feature/m12-ra82-performance-modernization`:
1. **P0 Network Outage Investigation & RCA (`reports/M12_NETWORK_OUTAGE_RCA.md`):** Reconstructed forensic timeline. Proved 1h 43m quiet gap between audit completion (17:31:59) and router reboot (19:15:30) with ZERO agent SSH connections. Ruled out kernel OOM/panic (empty `crash` / `crash_syslog` mtd partitions). Confirmed hardware reboot (`flag_boot_type=2`, uptime 1064s at 19:33:16). Confirmed client Wi-Fi loss was normal post-reboot radio convergence and WAN DHCP acquisition. Confirmed workstation UDP ephemeral port exhaustion (Windows Event ID 4266) caused the github.com DNS resolution timeout.
2. **Operational Safety Specification (`docs/M12_ROUTER_ACCESS_SAFETY.md`):** Enforced single-agent sequential SSH policy, zero parallel benchmarks, mandatory LAN health verification, and zero unattended router changes.
3. **Modular Optimization Framework Extended (`performance/profiles/`, 105/105 tests pass):** Added DNS Stability & Cache Profile (`dns_stability.sh`, 2048 cache, 512 forward-max, 300s min-cache-ttl, zero DHCP disruption via SIGHUP). Hardened NSS-aware tuning (`nss_flow_tuning.sh`) to prevent `auto_bypassed` and enforce dual-core queue affinities.
4. **PC-Side BoringTun Simulation & Verification (`tests/performance/test_wireguard_pc_simulation.sh`):** Statically linked ARMv7 binary with NEON SIMD. Executed dual-namespace QEMU simulation achieving 244.04 Mbps sustained TCP throughput, 0.00% packet loss, and zero memory leaks (+192 kB working buffer growth). Hardened setup/teardown scripts to strictly reject execution on active `wg0`.
5. **Strict Safety Protocol:** Zero router configuration writes, zero firmware flashing, zero NAND/NVRAM writes, zero unapproved router reboots. Lab directory `D:\vibecode\test_wifi` remains 100% untouched. Status: `M12_INVESTIGATION_AND_PC_MODERNIZATION_COMPLETE_AWAITING_REVIEW`. STRICT HOLD FOR CHIEF ARCHITECT REVIEW.
